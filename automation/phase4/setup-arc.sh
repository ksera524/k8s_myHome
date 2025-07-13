#!/bin/bash

# GitHub Actions Runner Controller (ARC) セットアップスクリプト
# Phase 4.9で実行される

set -euo pipefail

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

# GitHub Personal Access Token確認・入力
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    print_status "GitHub Personal Access Tokenが必要です"
    echo "GitHub Personal Access Token (repo, workflow, admin:org権限必要):"
    echo "取得方法: https://github.com/settings/tokens"
    echo -n "GITHUB_TOKEN: "
    read -s GITHUB_TOKEN
    echo ""
    
    if [[ -z "$GITHUB_TOKEN" ]]; then
        print_error "GITHUB_TOKENが入力されませんでした"
        exit 1
    fi
    
    export GITHUB_TOKEN
    print_debug "GITHUB_TOKEN設定完了"
else
    print_debug "GITHUB_TOKEN環境変数を使用"
fi

# GitHubユーザー名確認・入力
if [[ -z "${GITHUB_USERNAME:-}" ]]; then
    print_status "GitHubユーザー名を入力してください"
    echo -n "GITHUB_USERNAME: "
    read GITHUB_USERNAME
    
    if [[ -z "$GITHUB_USERNAME" ]]; then
        print_error "GITHUB_USERNAMEが入力されませんでした"
        exit 1
    fi
    
    export GITHUB_USERNAME
    print_debug "GITHUB_USERNAME設定完了: $GITHUB_USERNAME"
else
    print_debug "GITHUB_USERNAME環境変数を使用: $GITHUB_USERNAME"
fi

# Harbor認証情報確認・入力
print_status "Harbor認証情報を設定してください"

if [[ -z "${HARBOR_USERNAME:-}" ]]; then
    echo "Harbor Registry Username (default: admin):"
    echo -n "HARBOR_USERNAME [admin]: "
    read HARBOR_USERNAME_INPUT
    if [[ -z "$HARBOR_USERNAME_INPUT" ]]; then
        HARBOR_USERNAME="admin"
    else
        HARBOR_USERNAME="$HARBOR_USERNAME_INPUT"
    fi
    export HARBOR_USERNAME
    print_debug "HARBOR_USERNAME設定完了: $HARBOR_USERNAME"
else
    print_debug "HARBOR_USERNAME環境変数を使用: $HARBOR_USERNAME"
fi

if [[ -z "${HARBOR_PASSWORD:-}" ]]; then
    echo "Harbor Registry Password (default: Harbor12345):"
    echo -n "HARBOR_PASSWORD [Harbor12345]: "
    read -s HARBOR_PASSWORD_INPUT
    echo ""
    if [[ -z "$HARBOR_PASSWORD_INPUT" ]]; then
        HARBOR_PASSWORD="Harbor12345"
    else
        HARBOR_PASSWORD="$HARBOR_PASSWORD_INPUT"
    fi
    export HARBOR_PASSWORD
    print_debug "HARBOR_PASSWORD設定完了"
else
    print_debug "HARBOR_PASSWORD環境変数を使用"
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

# 1. Helmインストール確認
print_debug "Helmの確認中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
if ! command -v helm &> /dev/null; then
    echo "Helmをインストール中..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
    echo "✓ Helm既にインストール済み"
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

# GitHub Token Secret作成
kubectl create secret generic github-token \
  --from-literal=github_token=${GITHUB_TOKEN} \
  -n arc-systems \
  --dry-run=client -o yaml | kubectl apply -f -

# Harbor認証Secret作成
kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=192.168.122.100 \
  --docker-username=${HARBOR_USERNAME} \
  --docker-password=${HARBOR_PASSWORD} \
  -n arc-systems \
  --dry-run=client -o yaml | kubectl apply -f -

# Harbor認証Secret（GitHub Actions用）作成
kubectl create secret generic harbor-auth \
  --from-literal=HARBOR_USERNAME=${HARBOR_USERNAME} \
  --from-literal=HARBOR_PASSWORD=${HARBOR_PASSWORD} \
  -n arc-systems \
  --dry-run=client -o yaml | kubectl apply -f -

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

# 5. Runner Scale Sets作成
print_status "Runner Scale Setsを作成中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << EOF
# k8s_myHome用Runner Scale Set
helm install k8s-myhome-runners \
  --namespace arc-systems \
  --set githubConfigUrl="https://github.com/${GITHUB_USERNAME}/k8s_myHome" \
  --set githubConfigSecret="github-token" \
  --set containerMode.type="dind" \
  --set runnerScaleSetName="k8s-myhome-runners" \
  --set minRunners=0 \
  --set maxRunners=3 \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set || \
echo "k8s-myhome-runners既にインストール済み"

# slack.rs用Runner Scale Set (存在する場合)
if curl -s -f -H "Authorization: token ${GITHUB_TOKEN}" \
  "https://api.github.com/repos/${GITHUB_USERNAME}/slack.rs" > /dev/null 2>&1; then
  
  helm install slack-rs-runners \
    --namespace arc-systems \
    --set githubConfigUrl="https://github.com/${GITHUB_USERNAME}/slack.rs" \
    --set githubConfigSecret="github-token" \
    --set containerMode.type="dind" \
    --set runnerScaleSetName="slack-rs-runners" \
    --set minRunners=0 \
    --set maxRunners=3 \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set || \
  echo "slack-rs-runners既にインストール済み"
else
  echo "slack.rsリポジトリが見つからない、スキップします"
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

# 6.5. Harbor証明書修正（GitHub Actions対応）
print_status "=== Harbor証明書修正 + GitHub Actions対応 ==="
print_debug "GitHub Actionsからの証明書エラーを自動解決します"

# Harbor存在確認
print_debug "Harbor稼働状況を確認中..."
if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get namespace harbor' >/dev/null 2>&1; then
    # Harbor証明書修正スクリプトを実行
    if [[ -f "./harbor-cert-fix.sh" ]]; then
        print_debug "Harbor証明書修正スクリプトを実行中..."
        ./harbor-cert-fix.sh
        print_status "✓ Harbor証明書修正完了"
    else
        print_warning "harbor-cert-fix.shが見つかりません"
        print_debug "手動実行: automation/phase4/harbor-cert-fix.sh"
    fi
else
    print_warning "Harborがまだデプロイされていません"
    print_debug "ArgoCD App of Appsでのデプロイ完了後に以下を実行してください："
    print_debug "cd automation/phase4 && ./harbor-cert-fix.sh"
    print_warning "この状態でもGitHub Actionsランナーは利用可能ですが、Harbor pushでエラーが発生する可能性があります"
fi

# 7. 使用方法の表示
print_status "=== 使用方法 ==="
echo ""
echo "GitHub Actions workflowで以下のように指定してください："
echo ""
echo "jobs:"
echo "  build:"
echo "    runs-on: k8s-myhome-runners  # k8s_myHomeリポジトリ用"
echo "    # または"
echo "    runs-on: slack-rs-runners    # slack.rsリポジトリ用"
echo ""
echo "Harbor用環境変数:"
echo "- HARBOR_URL: 192.168.122.100"
echo "- HARBOR_PROJECT: sandbox"
echo ""
echo "Harbor認証："
echo "  docker login 192.168.122.100 -u $HARBOR_USERNAME -p $HARBOR_PASSWORD"
echo ""

# 8. GitHub Actions workflow例を保存 (最新のcrane方式)
cat > github-actions-example.yml << EOF
# GitHub Actions workflow例 - Harbor対応版
# .github/workflows/build-and-push.yml として保存

name: Build and Push to Harbor

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  build-and-push:
    runs-on: k8s-myhome-runners  # Runner Scale Set名
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
      
    - name: Harbor接続確認
      env:
        HARBOR_USERNAME: \${{ secrets.HARBOR_USERNAME }}
        HARBOR_PASSWORD: \${{ secrets.HARBOR_PASSWORD }}
      run: |
        echo "=== Harbor API Connection Test ==="
        curl -k -u \$HARBOR_USERNAME:\$HARBOR_PASSWORD https://192.168.122.100/v2/_catalog
        curl -k -u \$HARBOR_USERNAME:\$HARBOR_PASSWORD https://192.168.122.100/api/v2.0/projects | jq '.[] | select(.name=="sandbox")'
        
    - name: Dockerイメージビルド
      env:
        HARBOR_USERNAME: \${{ secrets.HARBOR_USERNAME }}
        HARBOR_PASSWORD: \${{ secrets.HARBOR_PASSWORD }}
      run: |
        echo "=== Docker Image Build ==="
        
        # Docker認証設定
        mkdir -p ~/.docker
        echo '{"auths":{"192.168.122.100":{"auth":"'\$(echo -n \"\$HARBOR_USERNAME:\$HARBOR_PASSWORD\" | base64 -w 0)'"}}}' > ~/.docker/config.json
        
        # Dockerイメージビルド
        docker build -t 192.168.122.100/sandbox/\${{ github.event.repository.name }}:latest .
        docker build -t 192.168.122.100/sandbox/\${{ github.event.repository.name }}:\${{ github.sha }} .
        
    - name: Harborプッシュ（crane使用）
      env:
        HARBOR_USERNAME: \${{ secrets.HARBOR_USERNAME }}
        HARBOR_PASSWORD: \${{ secrets.HARBOR_PASSWORD }}
      run: |
        echo "=== Harbor Push with Crane ==="
        
        # DNS設定でharbor.local解決を有効化
        echo "192.168.122.100 harbor.local" | sudo tee -a /etc/hosts
        
        # Craneツールインストール
        curl -sL "https://github.com/google/go-containerregistry/releases/latest/download/go-containerregistry_Linux_x86_64.tar.gz" | tar xz -C /tmp
        chmod +x /tmp/crane
        
        # Crane認証（insecure registry対応）
        export CRANE_INSECURE=true
        /tmp/crane auth login 192.168.122.100 -u \$HARBOR_USERNAME -p \$HARBOR_PASSWORD --insecure
        
        # latestタグプッシュ
        docker save 192.168.122.100/sandbox/\${{ github.event.repository.name }}:latest -o /tmp/image-latest.tar
        /tmp/crane push /tmp/image-latest.tar 192.168.122.100/sandbox/\${{ github.event.repository.name }}:latest --insecure
        
        # commitハッシュタグプッシュ
        docker save 192.168.122.100/sandbox/\${{ github.event.repository.name }}:\${{ github.sha }} -o /tmp/image-commit.tar
        /tmp/crane push /tmp/image-commit.tar 192.168.122.100/sandbox/\${{ github.event.repository.name }}:\${{ github.sha }} --insecure
        
        echo "✅ Harbor push completed successfully"
        
    - name: プッシュ結果確認
      env:
        HARBOR_USERNAME: \${{ secrets.HARBOR_USERNAME }}
        HARBOR_PASSWORD: \${{ secrets.HARBOR_PASSWORD }}
      run: |
        echo "=== Harbor Push Verification ==="
        
        # latestタグ確認
        curl -k -u \$HARBOR_USERNAME:\$HARBOR_PASSWORD https://192.168.122.100/v2/sandbox/\${{ github.event.repository.name }}/tags/list
        
        # リポジトリ一覧確認
        curl -k -u \$HARBOR_USERNAME:\$HARBOR_PASSWORD "https://192.168.122.100/api/v2.0/projects/sandbox/repositories"
        
        echo "=== Deployment completed successfully ==="
EOF

print_status "GitHub Actions workflow例をgithub-actions-example.ymlに保存しました"
print_warning "リポジトリの.github/workflows/にコピーして使用してください"

echo ""
print_status "=== セットアップ完了 ==="
echo ""
echo "✅ 設定された認証情報:"
echo "   GitHub ユーザー名: $GITHUB_USERNAME"
echo "   GitHub Token: ${GITHUB_TOKEN:0:8}... (先頭8文字のみ表示)"
echo "   Harbor ユーザー名: $HARBOR_USERNAME"
echo "   Harbor パスワード: ${HARBOR_PASSWORD:0:3}... (先頭3文字のみ表示)"
echo ""
echo "✅ 作成されたRunner Scale Sets:"
echo "   - k8s-myhome-runners (k8s_myHomeリポジトリ用)"
echo "   - slack-rs-runners (slack.rsリポジトリ用、存在する場合)"
echo ""
echo "📝 次のステップ:"
echo "1. GitHub Repository Secretsを設定:"
echo "   - https://github.com/$GITHUB_USERNAME/k8s_myHome/settings/secrets/actions"
echo "   - HARBOR_USERNAME: $HARBOR_USERNAME"
echo "   - HARBOR_PASSWORD: (入力したパスワード)"
echo "2. github-actions-example.yml をリポジトリの.github/workflows/にコピー"
echo "3. ArgoCD App of AppsでのHarbor完全デプロイを確認"
echo "   kubectl get applications -n argocd"
echo "   kubectl get pods -n harbor"
echo "4. Harbor証明書修正（まだ未実行の場合）:"
echo "   cd automation/phase4 && ./harbor-cert-fix.sh"
echo "5. GitHub ActionsでCI/CDテスト実行"
echo "6. Harborでイメージ確認: https://192.168.122.100"