#!/bin/bash

# Pulumi ESC Personal Access Token 設定スクリプト
# 標準入力からPATを受け取り、Kubernetes Secretとして安全に保存

set -euo pipefail

# スクリプトディレクトリ取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 共通色設定スクリプトを読み込み
if [[ -f "$SCRIPT_DIR/../common-colors.sh" ]]; then
    source "$SCRIPT_DIR/../common-colors.sh"
elif [[ -f "/tmp/common-colors.sh" ]]; then
    source "/tmp/common-colors.sh"
else
    # フォールバック: 基本的なprint関数を定義
    print_status() { echo "ℹ️  $1"; }
    print_warning() { echo "⚠️  $1"; }
    print_error() { echo "❌ $1"; }
    print_debug() { echo "🔍 $1"; }
fi

# 引数処理
INTERACTIVE=false
FORCE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--interactive)
            INTERACTIVE=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            cat << 'EOF'
使用方法: ./setup-pulumi-pat.sh [オプション]

オプション:
  -i, --interactive    対話モードでPATを入力
  -f, --force         既存のSecretを強制上書き
  --dry-run           実際の変更は行わず、実行内容のみ表示
  -h, --help          このヘルプを表示

使用例:
  # 環境変数からPATを取得
  export PULUMI_ACCESS_TOKEN="pul-xxx..."
  ./setup-pulumi-pat.sh

  # 対話モードでPATを入力
  ./setup-pulumi-pat.sh --interactive

  # 標準入力からPATを受け取り
  echo "pul-xxx..." | ./setup-pulumi-pat.sh

  # ファイルからPATを読み込み
  ./setup-pulumi-pat.sh < pat-token.txt
EOF
            exit 0
            ;;
        *)
            print_error "不明なオプション: $1"
            echo "詳細は --help を参照してください"
            exit 1
            ;;
    esac
done

print_status "=== Pulumi ESC Personal Access Token 設定 ==="

# kubectl接続確認
if ! kubectl version --client >/dev/null 2>&1; then
    print_error "kubectl が見つかりません"
    exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
    print_error "Kubernetesクラスタに接続できません"
    exit 1
fi

print_status "✓ Kubernetesクラスタ接続確認完了"

# PAT取得（優先順位: 対話入力 > 標準入力 > 環境変数）
PULUMI_PAT=""

if [ "$INTERACTIVE" = true ]; then
    print_status "対話モードでPulumi ESC Personal Access Tokenを入力してください"
    echo "https://app.pulumi.com/account/tokens から取得できます"
    echo -n "Pulumi Access Token (pul-で始まる): "
    read -s PULUMI_PAT
    echo
elif [ ! -t 0 ]; then
    # 標準入力からの読み取り
    print_debug "標準入力からPulumi Access Tokenを読み取り中..."
    PULUMI_PAT=$(cat)
elif [ -n "${PULUMI_ACCESS_TOKEN:-}" ]; then
    # 環境変数からの取得
    print_debug "環境変数PULUMI_ACCESS_TOKENからトークンを取得中..."
    PULUMI_PAT="$PULUMI_ACCESS_TOKEN"
else
    print_error "Pulumi Access Tokenが提供されていません"
    echo ""
    echo "以下のいずれかの方法でトークンを提供してください："
    echo "  1. 対話モード: ./setup-pulumi-pat.sh --interactive"
    echo "  2. 環境変数: export PULUMI_ACCESS_TOKEN=\"pul-xxx...\" && ./setup-pulumi-pat.sh"
    echo "  3. 標準入力: echo \"pul-xxx...\" | ./setup-pulumi-pat.sh"
    echo "  4. ファイル入力: ./setup-pulumi-pat.sh < token-file.txt"
    exit 1
fi

# PAT形式検証
PULUMI_PAT=$(echo "$PULUMI_PAT" | tr -d '[:space:]')  # 空白文字を削除

if [ -z "$PULUMI_PAT" ]; then
    print_error "空のトークンが提供されました"
    exit 1
fi

if [[ ! "$PULUMI_PAT" =~ ^pul-[a-f0-9]{40}$ ]]; then
    print_warning "Pulumi Access Tokenの形式が正しく見えません（pul-で始まる40文字の16進数文字列である必要があります）"
    if [ "$FORCE" = false ]; then
        echo -n "続行しますか？ [y/N]: "
        read -r response
        case "$response" in
            [yY][eE][sS]|[yY])
                print_debug "ユーザーが続行を選択しました"
                ;;
            *)
                print_status "処理を中止しました"
                exit 0
                ;;
        esac
    fi
fi

print_status "✓ Pulumi Access Tokenを取得しました"

# 対象ネームスペースの定義
NAMESPACES=(
    "external-secrets-system"
    "harbor"
    "arc-systems"
)

# 各ネームスペースでの処理
for namespace in "${NAMESPACES[@]}"; do
    print_status "処理中: $namespace ネームスペース"
    
    # ネームスペース存在確認・作成
    if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
        print_debug "ネームスペース $namespace が存在しません。作成中..."
        if [ "$DRY_RUN" = false ]; then
            kubectl create namespace "$namespace"
        else
            echo "[DRY-RUN] kubectl create namespace $namespace"
        fi
        print_status "✓ ネームスペース $namespace を作成"
    else
        print_debug "ネームスペース $namespace は既に存在"
    fi
    
    # 既存Secret確認
    SECRET_NAME="pulumi-access-token"
    if kubectl get secret "$SECRET_NAME" -n "$namespace" >/dev/null 2>&1; then
        if [ "$FORCE" = true ]; then
            print_warning "既存のSecret $SECRET_NAME を上書きします"
            if [ "$DRY_RUN" = false ]; then
                kubectl delete secret "$SECRET_NAME" -n "$namespace"
            else
                echo "[DRY-RUN] kubectl delete secret $SECRET_NAME -n $namespace"
            fi
        else
            print_warning "Secret $SECRET_NAME が $namespace に既に存在します"
            echo -n "上書きしますか？ [y/N]: "
            read -r response
            case "$response" in
                [yY][eE][sS]|[yY])
                    if [ "$DRY_RUN" = false ]; then
                        kubectl delete secret "$SECRET_NAME" -n "$namespace"
                    else
                        echo "[DRY-RUN] kubectl delete secret $SECRET_NAME -n $namespace"
                    fi
                    print_debug "既存のSecretを削除しました"
                    ;;
                *)
                    print_debug "Secret $SECRET_NAME をスキップします"
                    continue
                    ;;
            esac
        fi
    fi
    
    # Secret作成
    print_debug "Secret $SECRET_NAME を作成中: $namespace"
    if [ "$DRY_RUN" = false ]; then
        kubectl create secret generic "$SECRET_NAME" \
            --from-literal=PULUMI_ACCESS_TOKEN="$PULUMI_PAT" \
            -n "$namespace"
        
        # ラベル付与（管理目的）
        kubectl label secret "$SECRET_NAME" \
            app.kubernetes.io/name=external-secrets \
            app.kubernetes.io/component=pulumi-esc-auth \
            app.kubernetes.io/managed-by=k8s-myhome-automation \
            -n "$namespace"
    else
        echo "[DRY-RUN] kubectl create secret generic $SECRET_NAME --from-literal=PULUMI_ACCESS_TOKEN=*** -n $namespace"
        echo "[DRY-RUN] kubectl label secret $SECRET_NAME ... -n $namespace"
    fi
    
    print_status "✓ Secret $SECRET_NAME を作成: $namespace"
done

# 作成結果確認
if [ "$DRY_RUN" = false ]; then
    print_status "=== 作成されたSecretの確認 ==="
    for namespace in "${NAMESPACES[@]}"; do
        if kubectl get secret pulumi-access-token -n "$namespace" >/dev/null 2>&1; then
            echo "  ✓ $namespace: pulumi-access-token"
            # Secret作成日時を表示
            CREATION_TIME=$(kubectl get secret pulumi-access-token -n "$namespace" -o jsonpath='{.metadata.creationTimestamp}')
            echo "    作成日時: $CREATION_TIME"
        else
            echo "  ❌ $namespace: pulumi-access-token (作成失敗)"
        fi
    done
else
    print_status "=== DRY-RUN モード完了 ==="
    echo "実際の変更は行われませんでした"
fi

# セキュリティ注意事項
print_status "=== セキュリティ注意事項 ==="
cat << 'EOF'
🔒 セキュリティのベストプラクティス:
1. Personal Access Tokenは定期的にローテーションしてください
2. トークンをコマンド履歴やログファイルに残さないよう注意してください
3. 不要になったトークンは Pulumi Console から削除してください
4. このトークンは ESC (Environments, Secrets, and Configuration) の読み取り専用権限のみを持つべきです

📋 次のステップ:
1. SecretStore設定: kubectl apply -f secretstores/pulumi-esc-secretstore.yaml
2. ExternalSecret設定: ./deploy-harbor-secrets.sh
3. 動作確認: ./test-harbor-secrets.sh

🔍 確認コマンド:
- Secretの存在確認: kubectl get secrets -A | grep pulumi-access-token
- SecretStore接続確認: kubectl get secretstores -A
- ExternalSecret同期確認: kubectl get externalsecrets -A
EOF

print_status "=== Pulumi ESC Personal Access Token 設定完了 ==="

# 環境変数のクリーンアップ（セキュリティ対策）
unset PULUMI_PAT
unset PULUMI_ACCESS_TOKEN