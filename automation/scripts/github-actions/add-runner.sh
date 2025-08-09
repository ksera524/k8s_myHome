#!/bin/bash

# GitHubリポジトリ用Runner追加スクリプト
# 使用方法: ./add-runner.sh <repository-name>

set -euo pipefail

# GitHub認証情報管理ユーティリティを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../argocd/github-auth-utils.sh"
source "$SCRIPT_DIR/../common-colors.sh"

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

    # マニフェストファイルをリモートにコピー
    scp -o StrictHostKeyChecking=no "/home/ksera/k8s_myHome/manifests/platform/github-actions/github-actions-rbac.yaml" k8suser@192.168.122.10:/tmp/

    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << EOF
# ServiceAccount確認・作成
if ! kubectl get serviceaccount github-actions-runner -n arc-systems >/dev/null 2>&1; then
    echo "ServiceAccount 'github-actions-runner' を作成中..."
    kubectl create serviceaccount github-actions-runner -n arc-systems
    
    # Secret読み取り権限付与
    kubectl apply -f /tmp/github-actions-rbac.yaml
fi

# Runner Scale Set作成
echo "Runner Scale Set '$RUNNER_NAME' を作成中..."
helm upgrade --install $RUNNER_NAME \
  --namespace arc-systems \
  --set githubConfigUrl="https://github.com/$GITHUB_USERNAME/$REPOSITORY_NAME" \
  --set githubConfigSecret="github-token" \
  --set containerMode.type="dind" \
  --set containerMode.kubernetesModeWork.volumeClaimTemplate.storageClassName="local-ssd" \
  --set containerMode.dockerdInRunner.args="{dockerd,--host=unix:///var/run/docker.sock,--group=\$(DOCKER_GROUP_GID)}" \
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
        
        # Harbor認証情報デバッグ
        echo "Harbor認証情報確認中..."
        echo "Username: \$HARBOR_USERNAME"
        echo "Password length: \${#HARBOR_PASSWORD}"
        echo "URL: \$HARBOR_URL"
        
        # Harbor CA証明書が配布されているか確認
        echo "Harbor CA証明書配布状況確認中..."
        if [ -f "/etc/docker/certs.d/\$HARBOR_URL/ca.crt" ]; then
          echo "✅ Harbor CA証明書が配布されています"
          echo "証明書詳細:"
          openssl x509 -in /etc/docker/certs.d/\$HARBOR_URL/ca.crt -subject -noout
          openssl x509 -in /etc/docker/certs.d/\$HARBOR_URL/ca.crt -text -noout | grep -A 2 "Subject Alternative Name"
        else
          echo "⚠️  Harbor CA証明書が見つかりません: /etc/docker/certs.d/\$HARBOR_URL/ca.crt"
          echo "証明書ディレクトリ内容:"
          ls -la /etc/docker/certs.d/ || echo "証明書ディレクトリが存在しません"
        fi
        
        # Docker設定確認
        echo "Docker設定確認中..."
        docker info | grep -i "registry" || echo "Registry設定情報なし"
        
        # Harbor CA証明書をcert-managerから取得してコンテナ内にコピー
        echo "Harbor CA証明書をcert-managerから取得中..."
        kubectl get secret ca-key-pair -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/harbor-ca.crt || \\
        kubectl get secret harbor-tls-secret -n harbor -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/harbor-ca.crt
        
        # CA証明書の内容を確認
        echo "CA証明書内容確認:"
        head -3 /tmp/harbor-ca.crt
        echo "..."
        tail -3 /tmp/harbor-ca.crt
        
        # Docker証明書ディレクトリを作成してCA証明書をコピー
        sudo mkdir -p /etc/docker/certs.d/\$HARBOR_URL
        sudo cp /tmp/harbor-ca.crt /etc/docker/certs.d/\$HARBOR_URL/ca.crt
        sudo chmod 644 /etc/docker/certs.d/\$HARBOR_URL/ca.crt
        
        # システムのCA証明書ストアにも追加
        sudo cp /tmp/harbor-ca.crt /usr/local/share/ca-certificates/harbor.crt
        sudo update-ca-certificates
        
        echo "✅ Harbor CA証明書設定完了"
        
        # Harbor認証テスト (HTTPS with CA証明書)
        echo "Harbor認証テスト中..."
        curl --cacert /etc/docker/certs.d/\$HARBOR_URL/ca.crt -u \$HARBOR_USERNAME:\$HARBOR_PASSWORD "https://\$HARBOR_URL/api/v2.0/users/current" || echo "Harbor HTTPS認証失敗"
        
        # Docker認証設定
        echo "Docker認証設定を更新中..."
        mkdir -p ~/.docker
        echo "{\"auths\":{\"\$HARBOR_URL\":{\"auth\":\"\$(echo -n \"\$HARBOR_USERNAME:\$HARBOR_PASSWORD\" | base64 -w 0)\"}},\"credHelpers\":{}}" > ~/.docker/config.json
        chmod 600 ~/.docker/config.json
        
        # Docker daemon設定をHTTP fallback付きで設定
        echo "Docker daemon設定を確認・更新中..."
        sudo mkdir -p /etc/docker
        if [ ! -f /etc/docker/daemon.json ]; then
          echo '{"insecure-registries": ["'\$HARBOR_URL'"]}' | sudo tee /etc/docker/daemon.json
        else
          sudo jq '. + {"insecure-registries": ["'\$HARBOR_URL'"]}' /etc/docker/daemon.json > /tmp/daemon.json.tmp
          sudo mv /tmp/daemon.json.tmp /etc/docker/daemon.json
        fi
        
        # Docker login実行（HTTPS優先、HTTP fallback）
        echo "Docker login実行中..."
        if echo "\$HARBOR_PASSWORD" | docker login https://\$HARBOR_URL --username "\$HARBOR_USERNAME" --password-stdin; then
          echo "✅ HTTPS Docker login成功"
        else
          echo "⚠️ HTTPS login失敗、HTTP接続でリトライ中..."
          echo "\$HARBOR_PASSWORD" | docker login http://\$HARBOR_URL --username "\$HARBOR_USERNAME" --password-stdin || echo "Docker login完全失敗、継続"
        fi
        
        # Docker環境変数設定
        export DOCKER_CONTENT_TRUST=0
        
        echo "✅ Harbor Login & Docker設定完了"
        
    - name: Docker Build
      run: |
        echo "=== Docker Build ==="
        
        HARBOR_URL=\$(cat /tmp/harbor_url)
        HARBOR_PROJECT=\$(cat /tmp/harbor_project)
        
        # Dockerイメージビルド（HTTPS接続用）
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
        
        # Docker環境変数設定
        export DOCKER_CONTENT_TRUST=0
        
        # Harbor エンドポイントテスト（HTTPS優先、HTTP fallback）
        echo "Harbor エンドポイントをテスト中..."
        if curl --cacert /etc/docker/certs.d/\$HARBOR_URL/ca.crt -s -I https://\$HARBOR_URL/v2/ >/dev/null 2>&1; then
          echo "✅ Harbor HTTPS接続テスト成功"
          HARBOR_PROTOCOL="https"
        else
          echo "⚠️ Harbor HTTPS接続テスト失敗、HTTP接続テスト中..."
          if curl -s -I http://\$HARBOR_URL/v2/ >/dev/null 2>&1; then
            echo "✅ Harbor HTTP接続テスト成功"
            HARBOR_PROTOCOL="http"
          else
            echo "❌ Harbor HTTP接続テストも失敗"
            HARBOR_PROTOCOL="https"  # デフォルトHTTPS
          fi
        fi
        
        # Harbor認証テスト
        echo "Harbor API認証テスト中..."
        if [ "\$HARBOR_PROTOCOL" = "https" ]; then
          curl --cacert /etc/docker/certs.d/\$HARBOR_URL/ca.crt -u \$HARBOR_USERNAME:\$HARBOR_PASSWORD "https://\$HARBOR_URL/api/v2.0/users/current" || echo "Harbor API認証失敗"
        else
          curl -u \$HARBOR_USERNAME:\$HARBOR_PASSWORD "http://\$HARBOR_URL/api/v2.0/users/current" || echo "Harbor API認証失敗"
        fi
        
        # Docker pushを実行（プロトコル自動選択）
        echo "Docker pushで\${HARBOR_PROTOCOL}接続を使用してHarborにpush中..."
        
        echo "推す対象: \$HARBOR_URL/\$HARBOR_PROJECT/${REPOSITORY_NAME}:latest"
        if ! docker push \$HARBOR_URL/\$HARBOR_PROJECT/${REPOSITORY_NAME}:latest; then
          echo "⚠️ 最初のpush失敗、リトライ中..."
          if [ "\$HARBOR_PROTOCOL" = "https" ]; then
            # HTTPS失敗時はHTTPで再試行
            echo "\$HARBOR_PASSWORD" | docker login http://\$HARBOR_URL --username "\$HARBOR_USERNAME" --password-stdin
            docker push \$HARBOR_URL/\$HARBOR_PROJECT/${REPOSITORY_NAME}:latest || echo "HTTPでのpushも失敗"
          fi
        fi
        
        echo "推す対象: \$HARBOR_URL/\$HARBOR_PROJECT/${REPOSITORY_NAME}:\${{ github.sha }}"
        if ! docker push \$HARBOR_URL/\$HARBOR_PROJECT/${REPOSITORY_NAME}:\${{ github.sha }}; then
          echo "⚠️ 2番目のpush失敗、リトライ中..."
          if [ "\$HARBOR_PROTOCOL" = "https" ]; then
            # HTTPS失敗時はHTTPで再試行
            docker push \$HARBOR_URL/\$HARBOR_PROJECT/${REPOSITORY_NAME}:\${{ github.sha }} || echo "HTTPでのpushも失敗"
          fi
        fi
        
        echo "✅ Docker pushが成功しました"
        
        echo "✅ Harbor Push完了"
        
    - name: プッシュ結果確認
      run: |
        echo "=== プッシュ結果確認 ==="
        
        HARBOR_USERNAME=\$(cat /tmp/harbor_username)
        HARBOR_PASSWORD=\$(cat /tmp/harbor_password)
        HARBOR_URL=\$(cat /tmp/harbor_url)
        HARBOR_PROJECT=\$(cat /tmp/harbor_project)
        
        # プッシュされたイメージ確認（プロトコル自動選択）
        if [ "\$HARBOR_PROTOCOL" = "https" ]; then
          curl --cacert /etc/docker/certs.d/\$HARBOR_URL/ca.crt -u \$HARBOR_USERNAME:\$HARBOR_PASSWORD https://\$HARBOR_URL/v2/\$HARBOR_PROJECT/${REPOSITORY_NAME}/tags/list
        else
          curl -u \$HARBOR_USERNAME:\$HARBOR_PASSWORD http://\$HARBOR_URL/v2/\$HARBOR_PROJECT/${REPOSITORY_NAME}/tags/list
        fi
        
        echo "✅ デプロイ完了"
        
    - name: クリーンアップ
      if: always()
      run: |
        echo "=== クリーンアップ ==="
        
        # 認証情報ファイルを安全に削除
        rm -f /tmp/harbor_* /tmp/kubeconfig /tmp/image-*.tar /tmp/harbor-ca.crt
        
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
echo "   - Harbor HTTPS/HTTP自動選択認証とpush対応（CA証明書配布）"
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