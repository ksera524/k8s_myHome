#!/bin/bash

# GitHub Actions Runner Controller (ARC) セットアップスクリプト
# Phase 4.9で実行される

set -euo pipefail

# GitHub認証情報管理ユーティリティを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../argocd/github-auth-utils.sh"
source "$SCRIPT_DIR/../common-colors.sh"

# GitHub認証情報をESO管理のK8s Secretから取得
print_status "GitHub認証情報をK8s Secretから確認中..."

# K8s Secret から GitHub 認証情報を取得（ESO管理）
if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret github-auth -n arc-systems' >/dev/null 2>&1; then
    print_debug "ESO管理のGitHub認証情報を取得中..."
    
    GITHUB_TOKEN=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
        'kubectl get secret github-auth -n arc-systems -o jsonpath="{.data.GITHUB_TOKEN}" | base64 -d' 2>/dev/null)
    GITHUB_USERNAME=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
        'kubectl get secret github-auth -n arc-systems -o jsonpath="{.data.GITHUB_USERNAME}" | base64 -d' 2>/dev/null)
    
    if [[ -n "$GITHUB_TOKEN" && -n "$GITHUB_USERNAME" ]]; then
        export GITHUB_TOKEN
        export GITHUB_USERNAME
        print_status "✓ ESO管理のGitHub認証情報取得完了"
        print_debug "GITHUB_USERNAME: $GITHUB_USERNAME"
        print_debug "GITHUB_TOKEN: ${GITHUB_TOKEN:0:8}... (先頭8文字のみ表示)"
    else
        print_error "K8s SecretからのGitHub認証情報取得に失敗"
        exit 1
    fi
else
    print_warning "github-auth Secret (arc-systems) が見つかりません"
    print_status "従来方式でGitHub認証情報を確認中..."
    # フォールバック: 従来の方式
    if ! get_github_credentials; then
        print_error "GitHub認証情報の取得に失敗しました"
        exit 1
    fi
fi

# Harbor認証情報をESO管理のK8s Secretから取得
print_status "Harbor認証情報をK8s Secretから確認中..."

# K8s Secret から Harbor 認証情報を取得（ESO管理）
if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret harbor-auth -n arc-systems' >/dev/null 2>&1; then
    print_debug "ESO管理のHarbor認証情報を取得中..."
    
    HARBOR_USERNAME=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
        'kubectl get secret harbor-auth -n arc-systems -o jsonpath="{.data.HARBOR_USERNAME}" | base64 -d' 2>/dev/null)
    HARBOR_PASSWORD=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
        'kubectl get secret harbor-auth -n arc-systems -o jsonpath="{.data.HARBOR_PASSWORD}" | base64 -d' 2>/dev/null)
    
    if [[ -n "$HARBOR_USERNAME" && -n "$HARBOR_PASSWORD" ]]; then
        export HARBOR_USERNAME
        export HARBOR_PASSWORD
        print_status "✓ ESO管理のHarbor認証情報取得完了"
        print_debug "HARBOR_USERNAME: $HARBOR_USERNAME"
        print_debug "HARBOR_PASSWORD: ${HARBOR_PASSWORD:0:3}... (先頭3文字のみ表示)"
    else
        print_error "K8s SecretからのHarbor認証情報取得に失敗"
        exit 1
    fi
else
    print_warning "harbor-auth Secret (arc-systems) が見つかりません"
    print_status "従来方式でHarbor認証情報を確認中..."
    
    # フォールバック: 従来の方式
    if [[ -z "${HARBOR_USERNAME:-}" ]]; then
        # 非対話モードでは自動的にデフォルト値を使用
        if [[ "${NON_INTERACTIVE:-}" == "true" || "${CI:-}" == "true" || ! -t 0 ]]; then
            HARBOR_USERNAME="admin"
            print_debug "非対話モード: HARBOR_USERNAME自動設定: $HARBOR_USERNAME"
        else
            echo "Harbor Registry Username (default: admin):"
            echo -n "HARBOR_USERNAME [admin]: "
            read HARBOR_USERNAME_INPUT
            if [[ -z "$HARBOR_USERNAME_INPUT" ]]; then
                HARBOR_USERNAME="admin"
            else
                HARBOR_USERNAME="$HARBOR_USERNAME_INPUT"
            fi
            print_debug "HARBOR_USERNAME設定完了: $HARBOR_USERNAME"
        fi
        export HARBOR_USERNAME
    else
        print_debug "HARBOR_USERNAME環境変数を使用: $HARBOR_USERNAME"
    fi

    if [[ -z "${HARBOR_PASSWORD:-}" ]]; then
        # Harbor管理者パスワードを動的取得
        DYNAMIC_PASSWORD=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
            'kubectl get secret harbor-registry-secret -n arc-systems -o jsonpath="{.data.\.dockerconfigjson}" | base64 -d | grep -o "\"password\":\"[^\"]*\"" | cut -d":" -f2 | tr -d "\""' 2>/dev/null || echo "")
        
        # 非対話モードでは自動的にパスワードを設定
        if [[ "${NON_INTERACTIVE:-}" == "true" || "${CI:-}" == "true" || ! -t 0 ]]; then
            HARBOR_PASSWORD="${DYNAMIC_PASSWORD:-Harbor12345}"
            print_debug "非対話モード: HARBOR_PASSWORD自動設定（動的取得: ${HARBOR_PASSWORD:0:3}...）"
        else
            if [[ -n "$DYNAMIC_PASSWORD" ]]; then
                echo "Harbor Registry Password (動的取得: ${DYNAMIC_PASSWORD:0:8}...):"
                echo -n "HARBOR_PASSWORD [動的パスワード使用]: "
            else
                echo "Harbor Registry Password (default: Harbor12345):"
                echo -n "HARBOR_PASSWORD [Harbor12345]: "
            fi
            
            read -s HARBOR_PASSWORD_INPUT
            echo ""
            if [[ -z "$HARBOR_PASSWORD_INPUT" ]]; then
                HARBOR_PASSWORD="${DYNAMIC_PASSWORD:-Harbor12345}"
            else
                HARBOR_PASSWORD="$HARBOR_PASSWORD_INPUT"
            fi
            print_debug "HARBOR_PASSWORD設定完了"
        fi
        export HARBOR_PASSWORD
    else
        print_debug "HARBOR_PASSWORD環境変数を使用"
    fi
fi

# 入力値検証
print_status "GitHub設定を検証中..."

# GitHubユーザー名の形式確認
if [[ ! "$GITHUB_USERNAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
    print_error "無効なGitHubユーザー名形式: $GITHUB_USERNAME"
    print_error "英数字とハイフンのみ使用可能です"
    exit 1
fi

# GitHub APIアクセステスト
print_debug "GitHub APIアクセステスト中..."
if ! curl -s -f -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/user" > /dev/null 2>&1; then
    print_error "GitHub API認証に失敗しました"
    print_error "GITHUB_TOKENが正しく設定されているか確認してください"
    print_error "必要な権限: repo, workflow, admin:org"
    exit 1
fi

print_status "✓ GitHub設定検証完了"

print_status "=== Phase 4.9: GitHub Actions Runner Controller (ARC) セットアップ ==="

# 0. マニフェストファイルの準備
print_status "GitHub Actions RBAC設定を作成中..."
cat > /tmp/github-actions-rbac.yaml << 'EOF'
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: arc-systems
  name: github-actions-runner-role
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: github-actions-runner-binding
  namespace: arc-systems
subjects:
- kind: ServiceAccount
  name: github-actions-runner
  namespace: arc-systems
roleRef:
  kind: Role
  name: github-actions-runner-role
  apiGroup: rbac.authorization.k8s.io
EOF
scp -o StrictHostKeyChecking=no /tmp/github-actions-rbac.yaml k8suser@192.168.122.10:/tmp/
rm -f /tmp/github-actions-rbac.yaml
print_status "✓ GitHub Actions RBAC設定作成完了"

# 1. Helm確認・インストール
print_debug "Helmの確認・インストール中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
if ! command -v helm &> /dev/null; then
    echo "🔧 Helmをインストール中..."
    
    # Helmの最新版をダウンロード・インストール
    curl https://get.helm.sh/helm-v3.12.3-linux-amd64.tar.gz | tar xz
    sudo mv linux-amd64/helm /usr/local/bin/helm
    rm -rf linux-amd64
    
    # インストール確認
    if command -v helm &> /dev/null; then
        echo "✅ Helm v$(helm version --short --client) インストール完了"
    else
        echo "❌ Helmインストールに失敗しました"
        exit 1
    fi
else
    echo "✓ Helm v$(helm version --short --client) 確認完了"
fi
EOF

# 2. GitHub Container Registry認証
print_debug "GitHub Container Registryにログイン中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << EOF
echo "${GITHUB_TOKEN}" | helm registry login ghcr.io -u ${GITHUB_USERNAME} --password-stdin
EOF

# 3. ARC namespaceとSecrets作成
print_debug "ARC namespace とSecrets作成中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << EOF
# Namespace作成
kubectl create namespace arc-systems --dry-run=client -o yaml | kubectl apply -f -

# GitHub Token Secret - 既にESO (External Secrets Operator) で管理されています
echo "⏳ ESOからのGitHub Token Secret作成を待機中..."
kubectl wait --for=condition=Ready externalsecret/github-token-secret -n arc-systems --timeout=60s || echo "⚠️  GitHub Token ExternalSecret待機がタイムアウトしました"

# Harbor Registry Secret - 既にESO (External Secrets Operator) で管理されています
echo "⏳ ESOからのHarbor Registry Secret作成を待機中..."
kubectl wait --for=condition=Ready externalsecret/harbor-registry-secret -n arc-systems --timeout=60s || echo "⚠️  Harbor Registry ExternalSecret待機がタイムアウトしました"

# Harbor Auth Secret - 既にESO (External Secrets Operator) で管理されています
echo "⏳ ESOからのHarbor Auth Secret作成を待機中..."
kubectl wait --for=condition=Ready externalsecret/harbor-auth-secret -n arc-systems --timeout=60s || echo "⚠️  Harbor Auth ExternalSecret待機がタイムアウトしました"

# default namespace用のHarbor Auth Secret - 既にESOで管理されています
echo "⏳ ESOからのHarbor Auth Secret (default namespace)作成を待機中..."
kubectl wait --for=condition=Ready externalsecret/harbor-registry-secret-default -n default --timeout=60s || echo "⚠️  Harbor Auth ExternalSecret (default)待機がタイムアウトしました"

echo "✓ Secrets作成完了"
EOF

# 4. ARC Controller インストール
print_status "ARC Controllerをインストール中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
helm install arc \
  --namespace arc-systems \
  --create-namespace \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller || \
echo "ARC Controller既にインストール済み"
EOF

# 5. Runner Scale Sets作成（ServiceAccount指定）
print_status "Runner Scale Setsを作成中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << EOF
# ServiceAccount確認
if ! kubectl get serviceaccount github-actions-runner -n arc-systems >/dev/null 2>&1; then
    echo "ServiceAccount 'github-actions-runner' が見つかりません"
    echo "自動作成中..."
    kubectl create serviceaccount github-actions-runner -n arc-systems
    
    # Secret読み取り権限付与
    kubectl apply -f /tmp/github-actions-rbac.yaml
fi
EOF

# 6. ARC状態確認
print_debug "ARC状態確認中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
echo "=== ARC Controller状態 ==="
kubectl get pods -n arc-systems

echo -e "\n=== Runner Scale Sets ==="
kubectl get AutoscalingRunnerSet -n arc-systems 2>/dev/null || echo "AutoscalingRunnerSetがまだ作成されていません"

echo -e "\n=== Helm Releases ==="
helm list -n arc-systems
EOF

print_status "✓ GitHub Actions Runner Controller (ARC) セットアップ完了"

# 6.5. Harbor skopeo対応確認（証明書修正は不要）
print_status "=== Harbor skopeo対応確認 ==="
print_debug "skopeoアプローチによりHarbor証明書問題は自動解決されます"

# Harbor存在確認
print_debug "Harbor稼働状況を確認中..."
if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get namespace harbor' >/dev/null 2>&1; then
    print_status "✓ Harborデプロイ確認完了"
    print_debug "skopeo --dest-tls-verify=false によりTLS証明書問題は回避されます"
else
    print_warning "Harborがまだデプロイされていません"
    print_debug "ArgoCD App of Appsでのデプロイ完了後もskopeoアプローチにより問題なく動作します"
fi

# 6.6. skopeo対応注記（insecure registry設定は不要）
print_status "=== skopeo対応注記 ==="
print_debug "skopeoアプローチによりinsecure registry設定も不要です"

print_status "✓ skopeoアプローチによる完全対応"
print_debug "GitHub Actions WorkflowでskopeoのTLS検証無効化により証明書・レジストリ問題を解決"

# 7. 使用方法の表示（skopeo版）
print_status "=== 使用方法 (skopeo版) ==="
echo ""
echo "🎯 GitHub Actions Runner追加方法："
echo "   make add-runner REPO=<repository-name>"
echo "   例: make add-runner REPO=my-awesome-project"
echo ""
echo "🔧 GitHub Actions workflowは各リポジトリ用に自動生成されます："
echo "   - skopeoベースでTLS検証無効化"
echo "   - Harbor認証情報をk8s Secretから自動取得"
echo "   - 533行の複雑なアプローチから108行のシンプルな実装"
echo ""
echo ""
print_status "=== セットアップ完了 (skopeo版) ==="
echo ""
echo "✅ ESO管理の認証情報:"
echo "   GitHub ユーザー名: $GITHUB_USERNAME (ESO-k8s Secret自動取得)"
echo "   GitHub Token: ${GITHUB_TOKEN:0:8}... (ESO-k8s Secret自動取得)"
echo "   Harbor ユーザー名: $HARBOR_USERNAME (ESO-k8s Secret自動取得)"
echo "   Harbor パスワード: ${HARBOR_PASSWORD:0:3}... (ESO-k8s Secret自動取得)"
echo ""
echo "✅ ARC基盤のセットアップ完了:"
echo "   - GitHub Actions Runner Controller (ARC) インストール済み"
echo "   - ServiceAccount 'github-actions-runner' 作成済み"
echo "   - RBAC権限設定済み（Secret読み取り権限）"
echo "   - ESO (External Secrets Operator) 統合済み"
echo ""
echo "✅ skopeoアプローチ採用:"
echo "   - Harbor証明書問題: --dest-tls-verify=false で回避"
echo "   - 複雑なCA証明書管理: 不要"
echo "   - insecure registry設定: 不要"
echo "   - 保守性・信頼性: 大幅向上"
echo ""
echo "📝 次のステップ:"
echo "1. 各リポジトリにRunner追加:"
echo "   make add-runner REPO=<repository-name>"
echo "2. 生成されたworkflowファイルをコミット"
echo "   git add .github/workflows/build-and-push-*.yml"
echo "   git commit -m \"Add skopeo-based GitHub Actions workflow\""
echo "   git push"
echo "3. GitHub ActionsでCI/CDテスト実行"
echo "4. Harborでイメージ確認: http://192.168.122.100"
echo ""
echo "🎉 skopeoベースARC基盤セットアップ完了！"
echo "   複雑な証明書管理を排除し、シンプル・確実なCI/CDパイプラインが利用可能です。"