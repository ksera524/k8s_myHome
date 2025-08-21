#!/bin/bash

# GitHub Actions Runner Controller (ARC) セットアップスクリプト
# 動作確認済みHelm版で自動設定

set -euo pipefail

# 共通ライブラリを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPTS_ROOT/common-k8s-utils.sh"
source "$SCRIPTS_ROOT/common-colors.sh"

print_status "=== GitHub Actions Runner Controller セットアップ開始 ==="

# k8sクラスタ接続確認
print_debug "k8sクラスタ接続確認中..."
if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
    print_error "k8sクラスタに接続できません"
    exit 1
fi
print_status "✓ k8sクラスタ接続OK"

# Helm動作確認
print_debug "Helm動作確認中..."
if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'which helm' >/dev/null 2>&1; then
    print_status "Helmをインストール中..."
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash'
fi
print_status "✓ Helm準備完了"

# 名前空間作成
print_debug "arc-systems namespace確認・作成中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl create namespace arc-systems --dry-run=client -o yaml | kubectl apply -f -'

# GitHub認証Secret作成
print_debug "GitHub認証情報確認中..."
GITHUB_TOKEN=""
if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret github-token -n arc-systems' >/dev/null 2>&1; then
    GITHUB_TOKEN=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret github-token -n arc-systems -o jsonpath="{.data.github_token}" | base64 -d')
    print_status "✓ GitHub認証情報を既存secretから取得"
else
    print_error "GitHub認証情報が見つかりません。External Secrets Operatorが必要です"
    exit 1
fi

# GitHub multi-repo secret作成
print_debug "GitHub multi-repo secret作成中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl create secret generic github-multi-repo-secret --from-literal=github_token='$GITHUB_TOKEN' -n arc-systems --dry-run=client -o yaml | kubectl apply -f -"

# ServiceAccount・RBAC作成
print_debug "ServiceAccount・RBAC設定中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: github-actions-runner
  namespace: arc-systems
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: github-actions-secret-reader
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: github-actions-secret-reader
subjects:
- kind: ServiceAccount
  name: github-actions-runner
  namespace: arc-systems
roleRef:
  kind: ClusterRole
  name: github-actions-secret-reader
  apiGroup: rbac.authorization.k8s.io
EOF'

# ARC Controller チェック
print_status "🚀 ARC Controller 状態確認中..."
# GitOps管理のARC Controllerが存在するか確認
if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get deployment arc-controller-gha-rs-controller -n arc-systems' >/dev/null 2>&1; then
    print_debug "GitOps管理のARC Controllerが検出されました"
    # GitOps管理のControllerが動作しているか確認
    if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl wait --for=condition=available deployment/arc-controller-gha-rs-controller -n arc-systems --timeout=60s' >/dev/null 2>&1; then
        print_status "✓ GitOps管理のARC Controllerが正常に動作しています"
    else
        print_error "GitOps管理のARC Controllerが正常に動作していません"
    fi
elif ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'helm status arc-controller -n arc-systems' >/dev/null 2>&1; then
    print_debug "Helm管理のARC Controllerをアップグレード中..."
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'helm upgrade arc-controller oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller --namespace arc-systems'
else
    print_debug "ARC Controllerが存在しません。Helmでインストール中..."
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'helm install arc-controller oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller --namespace arc-systems --create-namespace'
fi

# settings.tomlからRunnerScaleSet設定を読み込んで作成
print_status "🏃 設定ベースRunnerScaleSet セットアップ中..."
print_debug "settings.tomlからリポジトリリストを読み込み中..."

SETTINGS_FILE="$SCRIPTS_ROOT/../settings.toml"
if [[ ! -f "$SETTINGS_FILE" ]]; then
    print_error "settings.tomlが見つかりません: $SETTINGS_FILE"
    exit 1
fi

# GitHubユーザー名を取得
GITHUB_USERNAME=$(grep '^username = ' "$SETTINGS_FILE" | head -1 | cut -d'"' -f2)
if [[ -z "$GITHUB_USERNAME" ]]; then
    print_error "settings.tomlのgithub.usernameが設定されていません"
    exit 1
fi
print_debug "GitHub Username: $GITHUB_USERNAME"

# arc_repositoriesセクションを解析してRunnerScaleSetを作成
print_debug "settings.toml解析中..."

# TOMLファイルから配列データを抽出（改善版）
ARC_REPOS_TEMP=$(sed -n '/^arc_repositories = \[/,/^\]/p' "$SETTINGS_FILE")

if [[ -z "$ARC_REPOS_TEMP" ]]; then
    print_warning "settings.tomlにarc_repositories設定が見つかりません"
    print_warning "RunnerScaleSetは作成されません"
else
    print_debug "arc_repositories設定を発見しました"
    print_debug "raw設定データ:"
    print_debug "$ARC_REPOS_TEMP"
    
    # 配列の各要素を処理（プロセス置換を使用してパイプの問題を回避）
    REPO_LINES=$(echo "$ARC_REPOS_TEMP" | grep -E '^\s*\[".*"\s*,.*\]')
    print_debug "抽出されたリポジトリ行:"
    print_debug "$REPO_LINES"
    
    REPO_COUNT=$(echo "$REPO_LINES" | wc -l)
    print_debug "処理対象リポジトリ数: $REPO_COUNT"
    COUNTER=0
    
    # 一時ファイルを使用して確実に全行処理
    TEMP_REPO_FILE="/tmp/arc_repos_$$"
    echo "$REPO_LINES" > "$TEMP_REPO_FILE"
    
    print_debug "一時ファイル内容確認:"
    while IFS= read -r num_line; do
        print_debug "$num_line"
    done < <(cat -n "$TEMP_REPO_FILE")
    
    while IFS= read -r line; do
        print_debug "ループ開始: [$line]"
        # 空行をスキップ
        if [[ -z "$line" ]]; then
            print_debug "空行をスキップ"
            continue
        fi
        
        COUNTER=$((COUNTER + 1))
        print_debug "🔍 処理中 ($COUNTER): $line"
        
        # 正規表現で配列要素を抽出: ["name", min, max, "description"]
        if [[ $line =~ \[\"([^\"]+)\",\ *([0-9]+),\ *([0-9]+), ]]; then
            REPO_NAME="${BASH_REMATCH[1]}"
            MIN_RUNNERS="${BASH_REMATCH[2]}"
            MAX_RUNNERS="${BASH_REMATCH[3]}"
            
            # Runner名を生成（小文字変換、ドット・アンダースコアをハイフンに変換）
            RUNNER_NAME="$(echo "${REPO_NAME}" | tr '[:upper:]._' '[:lower:]--')-runners"
            
            print_status "🏃 $REPO_NAME RunnerScaleSet セットアップ中..."
            print_debug "Runner名: $RUNNER_NAME (min:$MIN_RUNNERS, max:$MAX_RUNNERS)"
            
            # RunnerScaleSetを作成・アップグレード（個別実行で安定化）
            print_debug "RunnerScaleSet作成予定: $RUNNER_NAME"
            print_debug "GitHub URL: https://github.com/$GITHUB_USERNAME/$REPO_NAME" 
            print_debug "設定: min=$MIN_RUNNERS, max=$MAX_RUNNERS"
            
            # RunnerScaleSet設定を保存（後で一括実行）
            echo "$RUNNER_NAME:$GITHUB_USERNAME:$REPO_NAME:$MIN_RUNNERS:$MAX_RUNNERS" >> "/tmp/runners_to_create_$$"
            print_status "✓ $RUNNER_NAME 設定を保存"
        else
            print_debug "スキップ: 無効な形式 - $line"
        fi
    done < "$TEMP_REPO_FILE"
    
    # 一時ファイル削除
    rm -f "$TEMP_REPO_FILE"
    
    # 保存された設定でRunnerScaleSetを一括作成（改善版）
    RUNNERS_FILE="/tmp/runners_to_create_$$"
    if [[ -f "$RUNNERS_FILE" ]]; then
        print_status "🚀 RunnerScaleSet一括作成開始"
        print_debug "一時ファイル内容確認:"
        cat -n "$RUNNERS_FILE" | while read line; do print_debug "$line"; done
        
        # ファイルの各行を配列に読み込み
        readarray -t RUNNER_CONFIGS < "$RUNNERS_FILE"
        
        for config in "${RUNNER_CONFIGS[@]}"; do
            [[ -z "$config" ]] && continue
            
            IFS=':' read -r runner_name github_user repo_name min_runners max_runners <<< "$config"
            print_debug "一括作成処理: [$runner_name:$github_user:$repo_name:$min_runners:$max_runners]"
            
            print_status "🏃 $repo_name ($runner_name) を作成中..."
            
            # 個別にRunnerScaleSetを作成（set -eを無効化）
            set +e
            if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "helm status '$runner_name' -n arc-systems" >/dev/null 2>&1; then
                print_debug "既存の$runner_name をアップグレード中..."
                ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "helm upgrade '$runner_name' oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set --namespace arc-systems --set githubConfigUrl='https://github.com/$github_user/$repo_name' --set githubConfigSecret=github-multi-repo-secret --set maxRunners=$max_runners --set minRunners=$min_runners --set containerMode.type=dind --set template.spec.serviceAccountName=github-actions-runner"
                if [ $? -eq 0 ]; then
                    print_status "✓ $runner_name アップグレード完了"
                else
                    print_error "❌ $runner_name アップグレード失敗"
                fi
            else
                print_debug "新規$runner_name をインストール中..."
                ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "helm install '$runner_name' oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set --namespace arc-systems --set githubConfigUrl='https://github.com/$github_user/$repo_name' --set githubConfigSecret=github-multi-repo-secret --set maxRunners=$max_runners --set minRunners=$min_runners --set containerMode.type=dind --set template.spec.serviceAccountName=github-actions-runner"
                if [ $? -eq 0 ]; then
                    print_status "✓ $runner_name インストール完了"
                else
                    print_error "❌ $runner_name インストール失敗"
                fi
            fi
            set -e
        done
        
        rm -f "$RUNNERS_FILE"
    fi
    
    print_status "✓ 設定ベースRunnerScaleSet作成完了"
fi

# 状態確認
print_status "📊 ARC状態確認中..."
sleep 10

ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
echo "=== ARC Controller 状態 ==="
kubectl get deployment -n arc-systems

echo -e "\n=== RunnerScaleSets 状態 ==="
helm list -n arc-systems

echo -e "\n=== Pods 状態 ==="
kubectl get pods -n arc-systems

echo -e "\n=== AutoscalingRunnerSets 状態 ==="
kubectl get autoscalingrunnersets -n arc-systems 2>/dev/null || echo "AutoscalingRunnerSets CRDがまだ準備中..."
EOF

print_status "✅ GitHub Actions Runner Controller セットアップ完了"
print_status ""
print_status "📋 利用可能なRunnerScaleSet (settings.toml設定ベース):"

# 作成されたRunnerScaleSetを動的に表示
if [[ -n "$ARC_REPOS_TEMP" ]]; then
    SUMMARY_REPO_LINES=$(echo "$ARC_REPOS_TEMP" | grep -E '^\s*\[".*"\s*,.*\]')
    TEMP_SUMMARY_FILE="/tmp/arc_summary_$$"
    echo "$SUMMARY_REPO_LINES" > "$TEMP_SUMMARY_FILE"
    
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ $line =~ \[\"([^\"]+)\",\ *([0-9]+),\ *([0-9]+), ]]; then
            REPO_NAME="${BASH_REMATCH[1]}"
            MIN_RUNNERS="${BASH_REMATCH[2]}"
            MAX_RUNNERS="${BASH_REMATCH[3]}"
            RUNNER_NAME="$(echo "${REPO_NAME}" | tr '[:upper:]._' '[:lower:]--')-runners"
            print_status "   • $RUNNER_NAME - $REPO_NAME リポジトリ専用 (min:$MIN_RUNNERS, max:$MAX_RUNNERS)"
        fi
    done < "$TEMP_SUMMARY_FILE"
    
    rm -f "$TEMP_SUMMARY_FILE"
    
    print_status ""
    print_status "⭐ Workflow内での使用方法:"
    TEMP_WORKFLOW_FILE="/tmp/arc_workflow_$$"
    echo "$SUMMARY_REPO_LINES" > "$TEMP_WORKFLOW_FILE"
    
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ $line =~ \[\"([^\"]+)\",\ *([0-9]+),\ *([0-9]+), ]]; then
            REPO_NAME="${BASH_REMATCH[1]}"
            RUNNER_NAME="$(echo "${REPO_NAME}" | tr '[:upper:]._' '[:lower:]--')-runners"
            print_status "   runs-on: $RUNNER_NAME    # $REPO_NAME 専用"
        fi
    done < "$TEMP_WORKFLOW_FILE"
    
    rm -f "$TEMP_WORKFLOW_FILE"
else
    print_status "   (settings.tomlに設定がありません)"
fi

print_status ""
print_status "🔐 認証: Individual GitHub PAT (ESO管理)"
print_status "🐳 環境: Docker-in-Docker対応"
print_status "🚀 管理: Helm + settings.toml設定ベース"