#!/bin/bash

# GitHub Actions Runner Controller (ARC) - 新しいリポジトリ用Runner追加スクリプト
# 公式GitHub ARC対応版 - クリーンで簡潔な実装

set -euo pipefail

# 共通ライブラリを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPTS_ROOT/common-k8s-utils.sh"
source "$SCRIPTS_ROOT/common-logging.sh"

# 引数確認
if [[ $# -lt 1 ]]; then
    log_error "使用方法: $0 <repository-name> [min-runners] [max-runners]"
    log_error "例: $0 my-awesome-project 1 3"
    exit 1
fi

REPOSITORY_NAME="$1"
# デフォルト値を設定（引数が渡されない場合）
MIN_RUNNERS="${2:-1}"
MAX_RUNNERS="${3:-3}"
# Runner名生成（小文字変換、ドット・アンダースコアをハイフンに変換）
RUNNER_NAME="$(echo "${REPOSITORY_NAME}" | tr '[:upper:]._' '[:lower:]--')-runners"

log_status "=== GitHub Actions Runner追加スクリプト (公式ARC対応) ==="
log_debug "対象リポジトリ: $REPOSITORY_NAME"
log_debug "Runner名: $RUNNER_NAME"
log_debug "Min Runners: $MIN_RUNNERS"
log_debug "Max Runners: $MAX_RUNNERS"

# GitHubユーザー名を取得（settings.tomlから）
# settings.tomlはautomation直下にある
SETTINGS_FILE="$SCRIPTS_ROOT/../settings.toml"
if [[ ! -f "$SETTINGS_FILE" ]]; then
    # 別の場所も試す（プロジェクトルートから実行される場合）
    SETTINGS_FILE="$SCRIPTS_ROOT/../../settings.toml"
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        # platform-deploy.shから呼ばれる場合
        SETTINGS_FILE="$(dirname "$SCRIPTS_ROOT")/settings.toml"
        if [[ ! -f "$SETTINGS_FILE" ]]; then
            log_error "settings.tomlが見つかりません"
            log_error "automation/settings.tomlを作成してください"
            exit 1
        fi
    fi
fi

log_debug "settings.tomlファイル: $SETTINGS_FILE"
GITHUB_USERNAME=$(grep '^username = ' "$SETTINGS_FILE" | head -1 | cut -d'"' -f2)
if [[ -z "$GITHUB_USERNAME" ]]; then
    log_error "settings.tomlのgithub.usernameが設定されていません"
    log_error "ファイル: $SETTINGS_FILE"
    exit 1
fi
log_debug "GitHub Username: $GITHUB_USERNAME"

# k8sクラスタ接続確認
log_debug "k8sクラスタ接続確認中..."
if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
    log_error "k8sクラスタに接続できません"
    exit 1
fi
log_status "✓ k8sクラスタ接続OK"

# GitHub認証情報確認
log_debug "GitHub認証情報確認中..."
if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret github-auth -n arc-systems' >/dev/null 2>&1; then
    log_error "GitHub認証情報が見つかりません。make all を実行してください"
    exit 1
fi
log_status "✓ GitHub認証情報確認完了"

# Helm確認・インストール
log_debug "Helm確認中..."
if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'which helm' >/dev/null 2>&1; then
    log_status "Helmをインストール中..."
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash'
    log_status "✓ Helmインストール完了"
else
    log_debug "✓ Helm確認済み"
fi

# GitHub multi-repo secret確認/作成
log_debug "GitHub multi-repo secret確認中..."
if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret github-multi-repo-secret -n arc-systems' >/dev/null 2>&1; then
    log_debug "github-multi-repo-secret を作成中..."
    GITHUB_TOKEN=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret github-auth -n arc-systems -o jsonpath="{.data.GITHUB_TOKEN}" | base64 -d')
    if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl create secret generic github-multi-repo-secret --from-literal=github_token='$GITHUB_TOKEN' -n arc-systems"; then
        log_debug "✓ github-multi-repo-secret 作成完了"
    else
        log_warning "⚠️ github-multi-repo-secret は既に存在するか、作成に失敗しました"
    fi
else
    log_debug "✓ github-multi-repo-secret 確認済み"
fi

# ServiceAccount確認と作成
log_status "ServiceAccount確認中..."
if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get serviceaccount github-actions-runner -n arc-systems' >/dev/null 2>&1; then
    log_warning "ServiceAccount github-actions-runner が存在しません。作成中..."
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl create serviceaccount github-actions-runner -n arc-systems --dry-run=client -o yaml | kubectl apply -f -'
    log_status "✓ ServiceAccount作成完了"
fi

# Runner Scale Set作成
log_status "🏃 RunnerScaleSet作成中..."

# 既存のRunnerを削除（存在する場合）
if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "helm status '$RUNNER_NAME' -n arc-systems" >/dev/null 2>&1; then
    log_warning "既存の $RUNNER_NAME を削除中..."
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "helm uninstall '$RUNNER_NAME' -n arc-systems" || true
    sleep 5
fi

# RunnerScaleSetを作成（minRunners=1推奨）
log_status "🏃 Helm install実行中..."
HELM_INSTALL_RESULT=0
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "helm install $RUNNER_NAME oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set --namespace arc-systems --set githubConfigUrl='https://github.com/$GITHUB_USERNAME/$REPOSITORY_NAME' --set githubConfigSecret='github-multi-repo-secret' --set maxRunners=$MAX_RUNNERS --set minRunners=$MIN_RUNNERS --set containerMode.type=dind --set template.spec.serviceAccountName=github-actions-runner --set 'template.spec.hostAliases[0].ip=192.168.122.100' --set 'template.spec.hostAliases[0].hostnames[0]=harbor.local' --wait --timeout=60s" 2>/dev/null || HELM_INSTALL_RESULT=$?

# Helm installの結果をチェック
if [[ $HELM_INSTALL_RESULT -ne 0 ]]; then
    log_error "❌ RunnerScaleSet '$RUNNER_NAME' の作成に失敗しました"
    log_debug "Helm install failed with exit code: $HELM_INSTALL_RESULT"
    
    # デバッグ情報を出力
    log_debug "既存のHelm releasesを確認中..."
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "helm list -n arc-systems" || true
    
    log_debug "ARC Controller Podの状態を確認中..."
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl get pods -n arc-systems | grep controller" || true
    
    exit 1
fi

# GitHub Actions workflow作成
log_status "=== GitHub Actions workflow作成 ==="

WORKFLOW_DIR=".github/workflows"
WORKFLOW_FILE="$WORKFLOW_DIR/build-and-push-$REPOSITORY_NAME.yml"

# .github/workflowsディレクトリ作成
mkdir -p "$WORKFLOW_DIR"
log_debug "Workflowディレクトリ作成: $WORKFLOW_DIR"

# workflow.yamlファイル作成
log_debug "Workflowファイル作成中: $WORKFLOW_FILE"
cat > "$WORKFLOW_FILE" << WORKFLOW_EOF
# GitHub Actions workflow for $REPOSITORY_NAME
# Auto-generated by add-runner.sh (公式ARC対応版)

name: Build and Push to Harbor - $REPOSITORY_NAME

on:
  push:
    branches: [ master, main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  build-and-push:
    runs-on: $RUNNER_NAME  # Kubernetes Runner
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
      
    - name: Setup kubectl and Harbor credentials
      run: |
        echo "=== Setup kubectl and Harbor credentials ==="
        
        # Install kubectl
        echo "Installing kubectl..."
        curl -LO "https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
        
        # Configure kubectl for in-cluster access
        echo "Configuring kubectl..."
        export KUBECONFIG=/tmp/kubeconfig
        kubectl config set-cluster default \\
            --server=https://kubernetes.default.svc \\
            --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \\
            --kubeconfig=\$KUBECONFIG
        kubectl config set-credentials default \\
            --token=\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) \\
            --kubeconfig=\$KUBECONFIG
        kubectl config set-context default \\
            --cluster=default --user=default \\
            --kubeconfig=\$KUBECONFIG
        kubectl config use-context default --kubeconfig=\$KUBECONFIG
        
        # Get Harbor credentials
        echo "Getting Harbor credentials..."
        kubectl get secret harbor-auth -n arc-systems -o jsonpath='{.data.HARBOR_USERNAME}' | base64 -d > /tmp/harbor_username
        kubectl get secret harbor-auth -n arc-systems -o jsonpath='{.data.HARBOR_PASSWORD}' | base64 -d > /tmp/harbor_password
        kubectl get secret harbor-auth -n arc-systems -o jsonpath='{.data.HARBOR_URL}' | base64 -d > /tmp/harbor_url
        kubectl get secret harbor-auth -n arc-systems -o jsonpath='{.data.HARBOR_PROJECT}' | base64 -d > /tmp/harbor_project
        
        chmod 600 /tmp/harbor_*
        echo "✅ Harbor credentials retrieved successfully"
        
    - name: Build and push images using skopeo
      run: |
        echo "=== Build and push images using skopeo ==="
        
        HARBOR_USERNAME=\$(cat /tmp/harbor_username)
        HARBOR_PASSWORD=\$(cat /tmp/harbor_password)
        HARBOR_URL=\$(cat /tmp/harbor_url)
        HARBOR_PROJECT=\$(cat /tmp/harbor_project)
        
        # Install skopeo
        echo "Installing skopeo..."
        sudo apt-get update && sudo apt-get install -y skopeo
        
        # Build Docker images
        echo "Building Docker images..."
        docker build -t $REPOSITORY_NAME:latest .
        docker build -t $REPOSITORY_NAME:\${{ github.sha }} .
        
        # Push using skopeo - エラー修正: ポート番号を明示的に指定
        echo "Pushing to Harbor using skopeo..."
        docker save $REPOSITORY_NAME:latest > /tmp/$REPOSITORY_NAME-latest.tar
        docker save $REPOSITORY_NAME:\${{ github.sha }} > /tmp/$REPOSITORY_NAME-sha.tar
        
        # /etc/hostsにharbor.localを追加
        echo "192.168.122.100 harbor.local" | sudo tee -a /etc/hosts
        
        # Harborのポートを明示的に指定
        skopeo copy --insecure-policy --dest-tls-verify=false \\
          --dest-creds="\$HARBOR_USERNAME:\$HARBOR_PASSWORD" \\
          docker-archive:/tmp/$REPOSITORY_NAME-latest.tar \\
          docker://harbor.local:80/\$HARBOR_PROJECT/$REPOSITORY_NAME:latest
        
        skopeo copy --insecure-policy --dest-tls-verify=false \\
          --dest-creds="\$HARBOR_USERNAME:\$HARBOR_PASSWORD" \\
          docker-archive:/tmp/$REPOSITORY_NAME-sha.tar \\
          docker://harbor.local:80/\$HARBOR_PROJECT/$REPOSITORY_NAME:\${{ github.sha }}
        
        echo "✅ Images pushed successfully to Harbor"
        
    - name: Cleanup
      if: always()
      run: |
        echo "=== Cleanup ==="
        rm -f /tmp/harbor_* /tmp/kubeconfig /tmp/$REPOSITORY_NAME-*.tar
        echo "✅ Cleanup completed"
WORKFLOW_EOF

# 完了メッセージ
log_status "=== セットアップ完了 ==="
log_status ""
log_status "✅ RunnerScaleSet作成:"
log_status "   - $RUNNER_NAME (minRunners=1, maxRunners=3)"
log_status "   - リポジトリ: https://github.com/$GITHUB_USERNAME/$REPOSITORY_NAME"
log_status ""
log_status "✅ GitHub Actions workflow作成:"
log_status "   - $WORKFLOW_FILE"
log_status ""
log_status "📝 次のステップ:"
log_status "1. GitHub リポジトリに Commit & Push"
log_status "   git add $WORKFLOW_FILE"
log_status "   git commit -m \"Add GitHub Actions workflow for $REPOSITORY_NAME\""
log_status "   git push"
log_status "2. GitHub ActionsでCI/CDテスト実行"
log_status "3. Harborでイメージ確認: http://192.168.122.100"
log_status ""
log_status "🎉 $REPOSITORY_NAME 用のRunner環境が準備完了しました！"