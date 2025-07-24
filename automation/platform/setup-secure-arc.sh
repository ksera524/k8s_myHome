#!/bin/bash

# セキュアなGitHub Actions Runner設定スクリプト
# パスワードとURLを安全に管理してARC設定とワークフロー生成

set -euo pipefail

echo "=== セキュアなGitHub Actions Runner設定 ==="

# 設定ファイルの場所
CONFIG_DIR="$HOME/.config/k8s-arc"
SECRETS_FILE="$CONFIG_DIR/secrets.env"
WORKFLOW_TEMPLATE_DIR="$(dirname "$0")/github-templates"

# 設定ディレクトリ作成
mkdir -p "$CONFIG_DIR"
mkdir -p "$WORKFLOW_TEMPLATE_DIR"

# セキュリティ設定関数
setup_security() {
    echo "=== セキュリティ設定 ==="
    
    # 設定ディレクトリの権限設定
    chmod 700 "$CONFIG_DIR"
    
    if [ -f "$SECRETS_FILE" ]; then
        chmod 600 "$SECRETS_FILE"
    fi
}

# GitHub認証情報の安全な入力
collect_github_credentials() {
    echo "=== GitHub認証情報の入力 ==="
    
    if [ -f "$SECRETS_FILE" ]; then
        echo "既存の設定が見つかりました。"
        echo "1) 既存設定を使用"
        echo "2) 新しい設定を入力"
        echo "3) 設定を表示（マスク済み）"
        read -p "選択してください (1-3): " choice
        
        case $choice in
            1)
                echo "既存設定を使用します。"
                return 0
                ;;
            2)
                echo "新しい設定を入力します。"
                ;;
            3)
                echo "現在の設定（マスク済み）:"
                if grep -q "GITHUB_TOKEN" "$SECRETS_FILE"; then
                    echo "GitHub Token: $(grep GITHUB_TOKEN "$SECRETS_FILE" | cut -d'=' -f2 | sed 's/./*/g')"
                fi
                if grep -q "GITHUB_REPO" "$SECRETS_FILE"; then
                    echo "GitHub Repository: $(grep GITHUB_REPO "$SECRETS_FILE" | cut -d'=' -f2)"
                fi
                if grep -q "HARBOR_PASSWORD" "$SECRETS_FILE"; then
                    echo "Harbor Password: $(grep HARBOR_PASSWORD "$SECRETS_FILE" | cut -d'=' -f2 | sed 's/./*/g')"
                fi
                read -p "続行しますか? (y/N): " continue_choice
                if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
                    exit 0
                fi
                return 0
                ;;
        esac
    fi
    
    echo "GitHub認証情報を入力してください:"
    
    # GitHub Personal Access Token
    while true; do
        read -s -p "GitHub Personal Access Token: " github_token
        echo
        if [ -n "$github_token" ]; then
            break
        fi
        echo "トークンを入力してください。"
    done
    
    # GitHub Repository
    read -p "GitHub Repository (例: username/repository): " github_repo
    
    # Harbor管理者パスワード
    read -s -p "Harbor管理者パスワード: " harbor_password
    echo
    
    # Harbor URL（デフォルト値）
    read -p "Harbor URL [http://192.168.122.100]: " harbor_url
    harbor_url=${harbor_url:-"http://192.168.122.100"}
    
    # Harbor Project（デフォルト値）
    read -p "Harbor Project [library]: " harbor_project
    harbor_project=${harbor_project:-"library"}
    
    # 設定ファイル作成
    cat > "$SECRETS_FILE" << EOF
# GitHub Actions Runner設定
GITHUB_TOKEN=$github_token
GITHUB_REPO=$github_repo

# Harbor Registry設定
HARBOR_URL=$harbor_url
HARBOR_USERNAME=admin
HARBOR_PASSWORD=$harbor_password
HARBOR_PROJECT=$harbor_project

# 生成日時
CREATED_AT=$(date -Iseconds)
EOF
    
    chmod 600 "$SECRETS_FILE"
    echo "認証情報を安全に保存しました: $SECRETS_FILE"
}

# ARC設定生成（CPU互換性最適化対応）
generate_arc_config() {
    echo "=== ARC設定生成（CPU互換性最適化対応） ==="
    
    # secrets.envから設定読み込み
    source "$SECRETS_FILE"
    
    # RunnerScaleSet設定生成（CPU互換性とDocker最適化を追加）
    cat > "$CONFIG_DIR/arc-runner-values.yaml" << EOF
# GitHub Actions Runner Controller設定（CPU互換性対応）
githubConfigUrl: https://github.com/$GITHUB_REPO
githubConfigSecret:
  github_token: "$GITHUB_TOKEN"

# Runner設定（CPU互換性 + Docker最適化）
template:
  spec:
    containers:
    - name: runner
      image: ghcr.io/actions/actions-runner:latest
      env:
      - name: DOCKER_HOST
        value: unix:///var/run/docker.sock
      - name: HARBOR_URL
        value: "$HARBOR_URL"
      - name: HARBOR_PROJECT
        value: "$HARBOR_PROJECT"
      # CPU互換性環境変数（QEMU Virtual CPU対応）
      - name: RUSTFLAGS
        value: "-C target-cpu=x86-64 -C target-feature=-aes,-avx,-avx2"
      - name: DOCKER_BUILDKIT_INLINE_CACHE
        value: "1"
      - name: DOCKER_CONTENT_TRUST
        value: "0"
      volumeMounts:
      - name: docker-sock
        mountPath: /var/run/docker.sock
      - name: harbor-ca
        mountPath: /usr/local/share/ca-certificates/harbor-ca.crt
        subPath: ca.crt
        readOnly: true
    # Docker-in-Docker initContainer に insecure registry設定を追加
    initContainers:
    - name: dind-config
      image: docker:dind
      command: ["sh", "-c"]
      args: 
      - |
        echo "Docker daemon設定中（CPU互換性 + insecure registry）..."
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json << DOCKER_EOF
        {
          "insecure-registries": ["$HARBOR_URL", "192.168.122.100"],
          "storage-driver": "overlay2",
          "default-runtime": "runc"
        }
        DOCKER_EOF
        echo "Docker daemon設定完了"
      volumeMounts:
      - name: docker-config
        mountPath: /etc/docker
    volumes:
    - name: docker-sock
      hostPath:
        path: /var/run/docker.sock
        type: Socket
    - name: harbor-ca
      configMap:
        name: harbor-ca-bundle
    - name: docker-config
      emptyDir: {}

# スケール設定
maxRunners: 3
minRunners: 1

# リソース設定（CPU互換性考慮）
resources:
  limits:
    cpu: 1000m
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 1Gi
EOF
    
    echo "ARC設定（CPU互換性最適化対応）を生成しました: $CONFIG_DIR/arc-runner-values.yaml"
}

# セキュアなワークフロー生成
generate_secure_workflow() {
    echo "=== セキュアなワークフロー生成 ==="
    
    source "$SECRETS_FILE"
    
    # GitHub Secrets設定手順
    cat > "$WORKFLOW_TEMPLATE_DIR/setup-github-secrets.md" << EOF
# GitHub Secrets設定手順

以下のSecretsをGitHubリポジトリに設定してください:

## 必須Secrets

1. **HARBOR_URL**
   - Value: \`$HARBOR_URL\`
   - 説明: Harbor レジストリのURL

2. **HARBOR_USERNAME**
   - Value: \`admin\`
   - 説明: Harbor 管理者ユーザー名

3. **HARBOR_PASSWORD**
   - Value: \`[Harbor管理者パスワード]\`
   - 説明: Harbor 管理者パスワード

4. **HARBOR_PROJECT**
   - Value: \`$HARBOR_PROJECT\`
   - 説明: Harbor プロジェクト名

## 設定方法

1. GitHubリポジトリページへ移動
2. Settings > Secrets and variables > Actions
3. "New repository secret" で上記Secretsを追加

## セキュリティ注意事項

- パスワードは絶対にワークフローファイルに直接記述しない
- Secretsは環境変数として参照する
- ログに機密情報が出力されないよう注意する
EOF

    # セキュアなワークフロー生成
    cat > "$WORKFLOW_TEMPLATE_DIR/harbor-build-push.yml" << 'EOF'
name: Build and Push to Harbor

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

env:
  # Harbor設定（Secretsから取得）
  HARBOR_URL: ${{ secrets.HARBOR_URL }}
  HARBOR_PROJECT: ${{ secrets.HARBOR_PROJECT }}
  
jobs:
  build-and-push:
    runs-on: self-hosted
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
    
    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3
    
    - name: Configure Harbor Trust & CPU Compatibility
      run: |
        # Harbor CA証明書の信頼設定 + CPU互換性設定（self-hosted runnerで必要）
        echo "Harbor証明書信頼設定 + CPU互換性設定中..."
        
        # CPU互換性環境変数設定（QEMU Virtual CPU対応）
        export RUSTFLAGS="-C target-cpu=x86-64 -C target-feature=-aes,-avx,-avx2"
        export DOCKER_BUILDKIT_INLINE_CACHE=1
        echo "CPU互換性設定: RUSTFLAGS=$RUSTFLAGS"
        
        # containerd設定確認
        if [ -f /etc/containerd/certs.d/192.168.122.100/hosts.toml ]; then
          echo "✓ Harbor Insecure Registry設定済み"
        else
          echo "⚠ Harbor Insecure Registry設定が必要"
        fi
    
    - name: Login to Harbor
      uses: docker/login-action@v3
      with:
        registry: ${{ secrets.HARBOR_URL }}
        username: ${{ secrets.HARBOR_USERNAME }}
        password: ${{ secrets.HARBOR_PASSWORD }}
    
    - name: Extract metadata
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: ${{ secrets.HARBOR_URL }}/${{ secrets.HARBOR_PROJECT }}/my-app
        tags: |
          type=ref,event=branch
          type=ref,event=pr
          type=sha,prefix={{branch}}-
          type=raw,value=latest,enable={{is_default_branch}}
    
    - name: Build and push Docker image
      uses: docker/build-push-action@v5
      with:
        context: .
        platforms: linux/amd64
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
        # CPU互換性のためのビルド引数（QEMU Virtual CPU対応）
        build-args: |
          RUSTFLAGS=-C target-cpu=x86-64 -C target-feature=-aes,-avx,-avx2
    
    - name: Security scan with Trivy
      run: |
        # Harbor Trivyスキャン実行
        echo "セキュリティスキャン実行中..."
        # 実際のスキャンはHarbor内蔵のTrivyで自動実行される
        echo "✓ Harborでのセキュリティスキャンが完了します"
    
    - name: Clean up
      if: always()
      run: |
        # ビルドキャッシュのクリーンアップ
        docker system prune -f
        echo "✓ クリーンアップ完了"
EOF

    # Kubernetesデプロイワークフロー
    cat > "$WORKFLOW_TEMPLATE_DIR/k8s-deploy.yml" << 'EOF'
name: Deploy to Kubernetes

on:
  workflow_run:
    workflows: ["Build and Push to Harbor"]
    types:
      - completed
    branches: [ main ]

env:
  HARBOR_URL: ${{ secrets.HARBOR_URL }}
  HARBOR_PROJECT: ${{ secrets.HARBOR_PROJECT }}
  KUBE_NAMESPACE: default

jobs:
  deploy:
    runs-on: self-hosted
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
    
    - name: Configure kubectl
      run: |
        # kubectl設定確認
        kubectl version --client
        kubectl get nodes
        echo "✓ Kubernetes接続確認完了"
    
    - name: Create Harbor Secret
      run: |
        # Harbor認証情報をKubernetesシークレットとして作成
        kubectl create secret docker-registry harbor-secret \
          --docker-server=${{ secrets.HARBOR_URL }} \
          --docker-username=${{ secrets.HARBOR_USERNAME }} \
          --docker-password=${{ secrets.HARBOR_PASSWORD }} \
          --namespace=$KUBE_NAMESPACE \
          --dry-run=client -o yaml | kubectl apply -f -
        
        echo "✓ Harbor認証シークレット作成完了"
    
    - name: Deploy to Kubernetes
      run: |
        # イメージタグ取得
        IMAGE_TAG=$(echo $GITHUB_SHA | cut -c1-8)
        IMAGE_NAME="${{ secrets.HARBOR_URL }}/${{ secrets.HARBOR_PROJECT }}/my-app:main-${IMAGE_TAG}"
        
        # デプロイメント更新
        kubectl set image deployment/my-app-deployment \
          my-app-container=$IMAGE_NAME \
          --namespace=$KUBE_NAMESPACE
        
        # ロールアウト状態確認
        kubectl rollout status deployment/my-app-deployment \
          --namespace=$KUBE_NAMESPACE \
          --timeout=300s
        
        echo "✓ デプロイメント完了: $IMAGE_NAME"
    
    - name: Verify deployment
      run: |
        # デプロイメント検証
        kubectl get pods --namespace=$KUBE_NAMESPACE -l app=my-app
        kubectl get services --namespace=$KUBE_NAMESPACE -l app=my-app
        
        echo "✓ デプロイメント検証完了"
EOF

    echo "セキュアなワークフローテンプレートを生成しました:"
    echo "  - セットアップ手順: $WORKFLOW_TEMPLATE_DIR/setup-github-secrets.md"
    echo "  - ビルド/プッシュ: $WORKFLOW_TEMPLATE_DIR/harbor-build-push.yml"
    echo "  - Kubernetesデプロイ: $WORKFLOW_TEMPLATE_DIR/k8s-deploy.yml"
}

# ARC Helmデプロイ
deploy_arc() {
    echo "=== ARC Helmデプロイ ==="
    
    source "$SECRETS_FILE"
    
    # Helm chartのインストール/更新
    echo "Actions Runner Controllerをデプロイ中..."
    
    # GitHub Personal Access TokenをKubernetesシークレットとして作成
    kubectl create secret generic github-secret \
        --from-literal=github_token="$GITHUB_TOKEN" \
        --namespace=arc-systems \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # RunnerScaleSetデプロイ
    helm upgrade --install arc-runner-set \
        oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
        --namespace arc-runners \
        --create-namespace \
        --values "$CONFIG_DIR/arc-runner-values.yaml" \
        --set githubConfigSecret.github_token="$GITHUB_TOKEN"
    
    echo "✓ ARC RunnerScaleSetデプロイ完了"
}

# メイン処理
main() {
    echo "GitHub Actions Runner セキュア設定スクリプト"
    echo "=============================================="
    
    # セキュリティ設定
    setup_security
    
    # 処理選択
    echo "実行する処理を選択してください:"
    echo "1) 初期設定（認証情報収集 + ARC設定生成）"
    echo "2) ワークフロー生成のみ"
    echo "3) ARCデプロイのみ"
    echo "4) 全て実行（設定 + ワークフロー + デプロイ）"
    echo "5) 設定表示"
    
    read -p "選択 (1-5): " main_choice
    
    case $main_choice in
        1)
            collect_github_credentials
            generate_arc_config
            generate_secure_workflow
            ;;
        2)
            if [ ! -f "$SECRETS_FILE" ]; then
                echo "認証情報が見つかりません。先に初期設定を実行してください。"
                exit 1
            fi
            generate_secure_workflow
            ;;
        3)
            if [ ! -f "$SECRETS_FILE" ]; then
                echo "認証情報が見つかりません。先に初期設定を実行してください。"
                exit 1
            fi
            deploy_arc
            ;;
        4)
            collect_github_credentials
            generate_arc_config
            generate_secure_workflow
            deploy_arc
            ;;
        5)
            if [ -f "$SECRETS_FILE" ]; then
                echo "設定ファイル: $SECRETS_FILE"
                echo "内容（マスク済み）:"
                grep -E "(GITHUB_REPO|HARBOR_URL|HARBOR_PROJECT|CREATED_AT)" "$SECRETS_FILE" || echo "設定情報なし"
            else
                echo "設定ファイルが見つかりません。"
            fi
            ;;
        *)
            echo "無効な選択です。"
            exit 1
            ;;
    esac
    
    echo ""
    echo "=== 設定完了 ==="
    echo "次の手順:"
    echo "1. GitHub Secretsを設定: $WORKFLOW_TEMPLATE_DIR/setup-github-secrets.md"
    echo "2. ワークフローファイルをリポジトリに配置"
    echo "3. Harbor Insecure Registry設定実行: ./configure-insecure-registry.sh"
    echo ""
    echo "設定ファイル場所: $CONFIG_DIR"
    echo "ワークフローテンプレート: $WORKFLOW_TEMPLATE_DIR"
    echo ""
    echo "✅ CPU互換性最適化機能:"
    echo "   - RUSTFLAGS: -C target-cpu=x86-64 -C target-feature=-aes,-avx,-avx2"
    echo "   - Docker BuildKit最適化対応"
    echo "   - QEMU Virtual CPU環境との互換性確保"
    echo "   - ARC Runner環境でのDocker-in-Docker最適化"
}

# スクリプト実行
main "$@"