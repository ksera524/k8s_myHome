#!/bin/bash

# GitHubリポジトリ用Runner追加スクリプト
# 使用方法: ./add-runner.sh <repository-name>

set -euo pipefail

# GitHub認証情報管理ユーティリティを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/github-auth-utils.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# 引数確認
if [[ $# -lt 1 ]] || [[ $# -gt 2 ]]; then
    print_error "使用方法: $0 <repository-name> [--skip-github-check]"
    print_error "例: $0 my-awesome-project"
    print_error "例: $0 my-awesome-project --skip-github-check"
    exit 1
fi

REPOSITORY_NAME="$1"
SKIP_GITHUB_CHECK="${2:-}"
RUNNER_NAME="${REPOSITORY_NAME}-runners"

print_status "=== GitHub Actions Runner追加スクリプト ==="
print_debug "対象リポジトリ: $REPOSITORY_NAME"
print_debug "Runner名: $RUNNER_NAME"

# GitHub設定の確認・取得（保存済みを利用または新規入力）
print_status "GitHub認証情報を確認中..."
if ! get_github_credentials; then
    print_error "GitHub認証情報の取得に失敗しました"
    exit 1
fi

# GitHubリポジトリ存在確認
if [[ "$SKIP_GITHUB_CHECK" == "--skip-github-check" ]]; then
    print_warning "GitHubリポジトリ存在確認をスキップします"
else
    print_debug "GitHubリポジトリ存在確認中..."
    if ! curl -s -f -H "Authorization: token $GITHUB_TOKEN" \
      "https://api.github.com/repos/$GITHUB_USERNAME/$REPOSITORY_NAME" > /dev/null 2>&1; then
        print_error "GitHubリポジトリが見つかりません: $GITHUB_USERNAME/$REPOSITORY_NAME"
        print_error "リポジトリ名とアクセス権限を確認してください"
        print_error "存在確認をスキップする場合は --skip-github-check オプションを使用してください"
        exit 1
    fi
    print_status "✓ GitHubリポジトリ確認完了: $GITHUB_USERNAME/$REPOSITORY_NAME"
fi

# k8sクラスタ接続確認
if [[ "$SKIP_GITHUB_CHECK" == "--skip-github-check" ]]; then
    print_warning "k8sクラスタ接続確認をスキップします（workflow作成のみ）"
else
    print_debug "k8sクラスタ接続確認中..."
    if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
        print_error "k8sクラスタに接続できません"
        exit 1
    fi
    print_status "✓ k8sクラスタ接続OK"
fi

# Runner Scale Set作成
if [[ "$SKIP_GITHUB_CHECK" == "--skip-github-check" ]]; then
    print_warning "Runner Scale Set作成をスキップします（workflow作成のみ）"
else
    # 既存Runner確認
    print_debug "既存Runner確認中..."
    EXISTING_RUNNER=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
        "helm list -n arc-systems | grep '$RUNNER_NAME' || echo ''")

    if [[ -n "$EXISTING_RUNNER" ]]; then
        print_warning "Runner '$RUNNER_NAME' は既に存在します"
        echo -n "上書きしますか？ (y/N): "
        read -r OVERWRITE
        if [[ "$OVERWRITE" != "y" && "$OVERWRITE" != "Y" ]]; then
            print_status "キャンセルしました"
            exit 0
        fi
        print_debug "既存Runnerを上書きします"
    fi

    print_status "=== Runner Scale Set作成 ==="
    print_debug "Runner名: $RUNNER_NAME"
    print_debug "対象リポジトリ: https://github.com/$GITHUB_USERNAME/$REPOSITORY_NAME"

    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << EOF
# ServiceAccount確認・作成
if ! kubectl get serviceaccount github-actions-runner -n arc-systems >/dev/null 2>&1; then
    echo "ServiceAccount 'github-actions-runner' を作成中..."
    kubectl create serviceaccount github-actions-runner -n arc-systems
    
    # Secret読み取り権限付与
    kubectl apply -f - <<RBAC
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: secret-reader
  namespace: arc-systems
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: github-actions-secret-reader
  namespace: arc-systems
subjects:
- kind: ServiceAccount
  name: github-actions-runner
  namespace: arc-systems
roleRef:
  kind: Role
  name: secret-reader
  apiGroup: rbac.authorization.k8s.io
RBAC
fi

# Runner Scale Set作成
echo "Runner Scale Set '$RUNNER_NAME' を作成中..."
helm upgrade --install $RUNNER_NAME \
  --namespace arc-systems \
  --set githubConfigUrl="https://github.com/$GITHUB_USERNAME/$REPOSITORY_NAME" \
  --set githubConfigSecret="github-token" \
  --set containerMode.type="dind" \
  --set runnerScaleSetName="$RUNNER_NAME" \
  --set template.spec.serviceAccountName="github-actions-runner" \
  --set minRunners=0 \
  --set maxRunners=3 \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set

echo "✓ Runner Scale Set '$RUNNER_NAME' 作成完了"
EOF

    # Runner状態確認
    print_debug "Runner状態確認中..."
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
echo "=== Runner Scale Sets 一覧 ==="
helm list -n arc-systems

echo -e "\n=== AutoscalingRunnerSet 状態 ==="
kubectl get AutoscalingRunnerSet -n arc-systems 2>/dev/null || echo "AutoscalingRunnerSetがまだ作成されていません"

echo -e "\n=== Runner Pods 状態 ==="
kubectl get pods -n arc-systems
EOF
fi

# GitHub Actions workflow作成
print_status "=== GitHub Actions workflow作成 ==="

WORKFLOW_DIR=".github/workflows"
WORKFLOW_FILE="$WORKFLOW_DIR/build-and-push-$REPOSITORY_NAME.yml"

# .github/workflowsディレクトリ作成
mkdir -p "$WORKFLOW_DIR"
print_debug "Workflowディレクトリ作成: $WORKFLOW_DIR"

# workflow.yamlファイル作成
print_debug "Workflowファイル作成中: $WORKFLOW_FILE"
cat > "$WORKFLOW_FILE" << WORKFLOW_EOF
# GitHub Actions workflow for ${REPOSITORY_NAME}
# Auto-generated by add-runner.sh

name: Build and Push to Harbor - ${REPOSITORY_NAME}

on:
  push:
    branches: [ master,main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  build-and-push:
    runs-on: ${RUNNER_NAME}  # Custom Runner Scale Set
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
      
    - name: kubectl インストール
      run: |
        echo "=== kubectl インストール ==="
        
        # kubectl の最新版をインストール
        curl -LO "https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
        
        # インストール確認
        kubectl version --client --output=yaml
        
        echo "✅ kubectl インストール完了"
        
    - name: Harbor認証情報取得
      run: |
        echo "=== Harbor認証情報取得 ==="
        
        # kubectl in-cluster設定
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
        
        # Harbor認証情報取得
        kubectl get secret harbor-auth -n arc-systems -o yaml | grep "HARBOR_USERNAME:" | awk '{print \$2}' | base64 -d > /tmp/harbor_username
        kubectl get secret harbor-auth -n arc-systems -o yaml | grep "HARBOR_PASSWORD:" | awk '{print \$2}' | base64 -d > /tmp/harbor_password
        kubectl get secret harbor-auth -n arc-systems -o yaml | grep "HARBOR_URL:" | awk '{print \$2}' | base64 -d > /tmp/harbor_url
        kubectl get secret harbor-auth -n arc-systems -o yaml | grep "HARBOR_PROJECT:" | awk '{print \$2}' | base64 -d > /tmp/harbor_project
        
        chmod 600 /tmp/harbor_*
        echo "✅ Harbor認証情報取得完了"
        
    - name: Harbor Login & Docker設定
      run: |
        echo "=== Harbor Login & Docker設定 ==="
        
        HARBOR_USERNAME=\$(cat /tmp/harbor_username)
        HARBOR_PASSWORD=\$(cat /tmp/harbor_password)
        HARBOR_URL=\$(cat /tmp/harbor_url)
        
        # /etc/hosts に Harbor エントリー追加
        echo "Harbor DNS設定を追加中..."
        echo "\$HARBOR_URL harbor.local" | sudo tee -a /etc/hosts
        
        # Docker認証設定ファイル作成
        mkdir -p ~/.docker
        echo "{\"auths\":{\"\$HARBOR_URL\":{\"auth\":\"\$(echo -n \"\$HARBOR_USERNAME:\$HARBOR_PASSWORD\" | base64 -w 0)\"}},\"credHelpers\":{},\"insecure-registries\":[\"\$HARBOR_URL\"]}" > ~/.docker/config.json
        chmod 600 ~/.docker/config.json
        
        # Docker client設定でinsecure registryを指定
        export DOCKER_CONTENT_TRUST=0
        
        echo "✅ Harbor Login & Docker設定完了"
        
    - name: Docker Build
      run: |
        echo "=== Docker Build ==="
        
        HARBOR_URL=\$(cat /tmp/harbor_url)
        HARBOR_PROJECT=\$(cat /tmp/harbor_project)
        
        # Dockerイメージビルド
        docker build -t \$HARBOR_URL/\$HARBOR_PROJECT/${REPOSITORY_NAME}:latest .
        docker build -t \$HARBOR_URL/\$HARBOR_PROJECT/${REPOSITORY_NAME}:\${{ github.sha }} .
        
        echo "✅ Docker Build完了"
        
    - name: Harbor Push
      run: |
        echo "=== Harbor Push ==="
        
        HARBOR_URL=\$(cat /tmp/harbor_url)
        HARBOR_PROJECT=\$(cat /tmp/harbor_project)
        HARBOR_USERNAME=\$(cat /tmp/harbor_username)
        HARBOR_PASSWORD=\$(cat /tmp/harbor_password)
        
        # Craneツールインストール（フォールバック用）
        echo "Craneツールをインストール中..."
        curl -sL "https://github.com/google/go-containerregistry/releases/latest/download/go-containerregistry_Linux_x86_64.tar.gz" | tar xz -C /tmp
        chmod +x /tmp/crane
        
        # Crane認証設定
        export CRANE_INSECURE=true
        /tmp/crane auth login \$HARBOR_URL -u \$HARBOR_USERNAME -p \$HARBOR_PASSWORD --insecure
        
        # Docker pushを試行（insecure registry設定済み）
        echo "Docker pushを試行中..."
        if docker push \$HARBOR_URL/\$HARBOR_PROJECT/${REPOSITORY_NAME}:latest && docker push \$HARBOR_URL/\$HARBOR_PROJECT/${REPOSITORY_NAME}:\${{ github.sha }}; then
            echo "✅ Docker pushが成功しました"
        else
            echo "Docker pushが失敗、craneを使用..."
            
            # Craneでイメージをpush（tarファイル経由）
            echo "latestタグをpush中..."
            docker save \$HARBOR_URL/\$HARBOR_PROJECT/${REPOSITORY_NAME}:latest -o /tmp/image-latest.tar
            /tmp/crane push /tmp/image-latest.tar \$HARBOR_URL/\$HARBOR_PROJECT/${REPOSITORY_NAME}:latest --insecure
            
            echo "commitハッシュタグをpush中..."
            docker save \$HARBOR_URL/\$HARBOR_PROJECT/${REPOSITORY_NAME}:\${{ github.sha }} -o /tmp/image-commit.tar
            /tmp/crane push /tmp/image-commit.tar \$HARBOR_URL/\$HARBOR_PROJECT/${REPOSITORY_NAME}:\${{ github.sha }} --insecure
            
            echo "✅ Crane pushが完了しました"
        fi
        
        echo "✅ Harbor Push完了"
        
    - name: プッシュ結果確認
      run: |
        echo "=== プッシュ結果確認 ==="
        
        HARBOR_USERNAME=\$(cat /tmp/harbor_username)
        HARBOR_PASSWORD=\$(cat /tmp/harbor_password)
        HARBOR_URL=\$(cat /tmp/harbor_url)
        HARBOR_PROJECT=\$(cat /tmp/harbor_project)
        
        # プッシュされたイメージ確認
        curl -k -u \$HARBOR_USERNAME:\$HARBOR_PASSWORD https://\$HARBOR_URL/v2/\$HARBOR_PROJECT/${REPOSITORY_NAME}/tags/list
        
        echo "✅ デプロイ完了"
        
    - name: クリーンアップ
      if: always()
      run: |
        echo "=== クリーンアップ ==="
        
        # 認証情報ファイルを安全に削除
        rm -f /tmp/harbor_* /tmp/kubeconfig /tmp/image-*.tar
        
        echo "✅ クリーンアップ完了"
WORKFLOW_EOF

# workflowファイル作成確認
if [[ -f "$WORKFLOW_FILE" ]]; then
    print_status "✅ Workflowファイル作成完了: $WORKFLOW_FILE"
else
    print_error "❌ Workflowファイル作成失敗: $WORKFLOW_FILE"
fi

print_status "=== セットアップ完了 ==="
echo ""
echo "✅ 作成されたRunner Scale Set:"
echo "   - $RUNNER_NAME"
echo "   - リポジトリ: https://github.com/$GITHUB_USERNAME/$REPOSITORY_NAME"
echo "   - ServiceAccount: github-actions-runner"
echo "   - 最小Runner数: 0"
echo "   - 最大Runner数: 3"
echo ""
echo "✅ 作成されたGitHub Actions workflow:"
echo "   - ファイル: $WORKFLOW_FILE"
echo "   - リポジトリ固有の設定済み"
echo "   - Harbor認証とpush対応"
echo ""
echo "📝 次のステップ:"
echo "1. GitHub リポジトリに Commit & Push"
echo "   git add $WORKFLOW_FILE"
echo "   git commit -m \"Add GitHub Actions workflow for $REPOSITORY_NAME\""
echo "   git push"
echo "2. GitHub ActionsでCI/CDテスト実行"
echo "3. Harborでイメージ確認: https://192.168.122.100"
echo ""
echo "🎉 $REPOSITORY_NAME 用のRunner環境が準備完了しました！"