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

# Harbor内部CA ConfigMap作成/更新
log_status "Harbor内部CA ConfigMap作成中..."
if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl -n arc-systems get configmap harbor-internal-ca' >/dev/null 2>&1; then
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl -n cert-manager get secret ca-key-pair -o jsonpath='{.data.ca\.crt}' | base64 -d | kubectl -n arc-systems create configmap harbor-internal-ca --from-file=ca.crt=/dev/stdin --dry-run=client -o yaml | kubectl apply -f -" >/dev/null
else
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl -n cert-manager get secret ca-key-pair -o jsonpath='{.data.ca\.crt}' | base64 -d | kubectl -n arc-systems create configmap harbor-internal-ca --from-file=ca.crt=/dev/stdin" >/dev/null
fi
log_status "✓ Harbor内部CA ConfigMap作成完了"

# Runner用Helm valuesファイル作成（内部CAをDockerに配布）
log_status "Runner用Helm valuesファイル作成中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "cat > /tmp/arc-runner-values.yaml << 'EOF'
template:
  spec:
    serviceAccountName: github-actions-runner
    hostAliases:
      - ip: 192.168.122.100
        hostnames:
          - harbor.internal.qroksera.com
    initContainers:
      - name: init-dind-externals
        image: ghcr.io/actions/actions-runner:latest
        command: ["cp"]
        args: ["-r", "/home/runner/externals/.", "/home/runner/tmpDir/"]
        volumeMounts:
          - name: dind-externals
            mountPath: /home/runner/tmpDir
      - name: dind
        image: docker:dind
        command: ["sh", "-c"]
        args:
          - |
            set -e
            cp /etc/docker/certs.d/harbor.internal.qroksera.com/ca.crt /usr/local/share/ca-certificates/harbor-internal-ca.crt
            update-ca-certificates
            dockerd --host=unix:///var/run/docker.sock --group=\$(DOCKER_GROUP_GID) --insecure-registry=harbor.internal.qroksera.com
        env:
          - name: DOCKER_GROUP_GID
            value: '123'
        securityContext:
          privileged: true
        restartPolicy: Always
        startupProbe:
          exec:
            command: ["docker", "info"]
          failureThreshold: 24
          periodSeconds: 5
        volumeMounts:
          - name: work
            mountPath: /home/runner/_work
          - name: dind-sock
            mountPath: /var/run
          - name: dind-externals
            mountPath: /home/runner/externals
          - name: harbor-internal-ca
            mountPath: /etc/docker/certs.d/harbor.internal.qroksera.com
            readOnly: true
    containers:
      - name: runner
        image: ghcr.io/actions/actions-runner:latest
        command: ["/home/runner/run.sh"]
        env:
          - name: DOCKER_HOST
            value: 'unix:///var/run/docker.sock'
          - name: RUNNER_WAIT_FOR_DOCKER_IN_SECONDS
            value: '120'
        volumeMounts:
          - name: work
            mountPath: /home/runner/_work
          - name: dind-sock
            mountPath: /var/run
    volumes:
      - name: dind-sock
        emptyDir: {}
      - name: dind-externals
        emptyDir: {}
      - name: work
        emptyDir: {}
      - name: harbor-internal-ca
        configMap:
          name: harbor-internal-ca
          items:
            - key: ca.crt
              path: ca.crt
EOF" >/dev/null
log_status "✓ Runner用Helm valuesファイル作成完了"

# RunnerScaleSetを作成（minRunners=1推奨）
log_status "🏃 Helm install実行中..."
HELM_INSTALL_RESULT=0
  ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "helm install $RUNNER_NAME oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set --namespace arc-systems --values /tmp/arc-runner-values.yaml --set githubConfigUrl='https://github.com/$GITHUB_USERNAME/$REPOSITORY_NAME' --set githubConfigSecret='github-multi-repo-secret' --set maxRunners=$MAX_RUNNERS --set minRunners=$MIN_RUNNERS --set controllerServiceAccount.namespace=arc-systems --set controllerServiceAccount.name=arc-controller-gha-rs-controller --wait --timeout=60s" 2>/dev/null || HELM_INSTALL_RESULT=$?
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
# Auto-generated by add-runner.sh (公式ARC対応版) - Auto Semver版

name: Build and Push to Harbor - $REPOSITORY_NAME

on:
  push:
    branches: [ main, master ]
  pull_request:
    branches: [ main, master ]

permissions:
  contents: write  # タグの作成とpushに必要
  pull-requests: read

jobs:
  build-and-push:
    runs-on: $RUNNER_NAME  # Kubernetes Runner
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
      with:
        fetch-depth: 0  # 全履歴を取得してタグ情報を取得
      
    - name: Auto increment version
      id: version
      run: |
        # 最新のタグを取得（存在しない場合は0.0.0から開始）
        LATEST_TAG=\$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
        echo "Latest tag: \$LATEST_TAG"
        
        # v prefix を削除
        LATEST_VERSION=\${LATEST_TAG#v}
        
        # バージョンを分解
        IFS='.' read -r MAJOR MINOR PATCH <<< "\$LATEST_VERSION"
        
        if [[ "\${{ github.event_name }}" == "pull_request" ]]; then
          # PR時はビルドのみ、pushしない
          VERSION="pr-\${{ github.event.pull_request.number }}-\$(git rev-parse --short HEAD)"
          echo "version=\$VERSION" >> \$GITHUB_OUTPUT
          echo "should_push=false" >> \$GITHUB_OUTPUT
          echo "should_tag=false" >> \$GITHUB_OUTPUT
          echo "🔍 PR Build: \$VERSION (build only, no push)"
        else
          # main/masterへのpush時は自動的にパッチバージョンをインクリメント
          PATCH=\$((PATCH + 1))
          NEW_VERSION="\$MAJOR.\$MINOR.\$PATCH"
          
          echo "version=\$NEW_VERSION" >> \$GITHUB_OUTPUT
          echo "should_push=true" >> \$GITHUB_OUTPUT
          echo "should_tag=true" >> \$GITHUB_OUTPUT
          echo "📦 New Version: \$NEW_VERSION (auto-incremented from \$LATEST_VERSION)"
        fi
      
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
        kubectl get secret ca-key-pair -n cert-manager -o jsonpath='{.data.ca\.crt}' | base64 -d > /tmp/harbor_ca.crt
        
        chmod 600 /tmp/harbor_*
        echo "✅ Harbor credentials retrieved successfully"
        
    - name: Build and push images using Docker
      run: |
        echo "=== Build and push images using Docker ==="
        
        HARBOR_USERNAME=\$(cat /tmp/harbor_username)
        HARBOR_PASSWORD=\$(cat /tmp/harbor_password)
        HARBOR_URL="harbor.internal.qroksera.com"
        HARBOR_PROJECT=\$(cat /tmp/harbor_project)
        VERSION="\${{ steps.version.outputs.version }}"
        SHOULD_PUSH="\${{ steps.version.outputs.should_push }}"

        # 内部CAを信頼ストアに追加
        echo "Installing internal CA..."
        sudo cp /tmp/harbor_ca.crt /usr/local/share/ca-certificates/harbor-internal-ca.crt
        sudo update-ca-certificates

        # Docker用のCA設定
        echo "Configuring Docker CA..."
        sudo mkdir -p /etc/docker/certs.d/harbor.internal.qroksera.com
        sudo cp /tmp/harbor_ca.crt /etc/docker/certs.d/harbor.internal.qroksera.com/ca.crt
        
        # Build Docker images
        echo "Building Docker image with version: \$VERSION"
        docker build -t \$HARBOR_URL/\$HARBOR_PROJECT/$REPOSITORY_NAME:\$VERSION .
        docker build -t \$HARBOR_URL/\$HARBOR_PROJECT/$REPOSITORY_NAME:\${{ github.sha }} .
        docker tag \$HARBOR_URL/\$HARBOR_PROJECT/$REPOSITORY_NAME:\$VERSION \$HARBOR_URL/\$HARBOR_PROJECT/$REPOSITORY_NAME:latest

        # pushするかどうかの判定（PR時はpushしない）
        if [ "\$SHOULD_PUSH" == "false" ]; then
          echo "⏭️  Skipping push (PR build only)"
          exit 0
        fi

        # /etc/hostsにharbor.internal.qroksera.comを追加
        echo "192.168.122.100 harbor.internal.qroksera.com" | sudo tee -a /etc/hosts

        # Harborにログイン
        echo "Logging in to Harbor..."
        docker login \$HARBOR_URL -u "\$HARBOR_USERNAME" -p "\$HARBOR_PASSWORD"

        # Harborへpush
        echo "Pushing to Harbor..."
        docker push \$HARBOR_URL/\$HARBOR_PROJECT/$REPOSITORY_NAME:\$VERSION
        docker push \$HARBOR_URL/\$HARBOR_PROJECT/$REPOSITORY_NAME:\${{ github.sha }}
        docker push \$HARBOR_URL/\$HARBOR_PROJECT/$REPOSITORY_NAME:latest
        
        echo "✅ Images pushed successfully to Harbor"
        echo "📦 Pushed tags: \$VERSION, \${{ github.sha }}, latest"
        
    - name: Create and push git tag
      if: steps.version.outputs.should_tag == 'true'
      run: |
        VERSION="\${{ steps.version.outputs.version }}"
        
        # Gitの設定
        git config user.name "github-actions[bot]"
        git config user.email "github-actions[bot]@users.noreply.github.com"
        
        # タグを作成
        git tag -a "v\$VERSION" -m "Auto-generated version v\$VERSION"
        
        # タグをpush
        git push origin "v\$VERSION"
        
        echo "✅ Created and pushed tag: v\$VERSION"
        
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
log_status "   - $RUNNER_NAME (minRunners=$MIN_RUNNERS, maxRunners=$MAX_RUNNERS)"
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
log_status "3. Harborでイメージ確認: https://harbor.internal.qroksera.com"
log_status ""
log_status "🎉 $REPOSITORY_NAME 用のRunner環境が準備完了しました！"
