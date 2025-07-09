#!/bin/bash

# Sealed Secrets作成用スクリプト
# 使用方法: ./create-secrets.sh

set -e

# 色付きメッセージ関数
print_info() {
    echo -e "\033[1;34m[INFO]\033[0m $1"
}

print_warning() {
    echo -e "\033[1;33m[WARNING]\033[0m $1"
}

print_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
}

print_success() {
    echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}

# kubesealがインストールされているかチェック
if ! command -v kubeseal &> /dev/null; then
    print_error "kubeseal CLI が見つかりません。先にインストールしてください。"
    exit 1
fi

# Sealed Secrets Controllerが動作しているかチェック
if ! kubectl get pods -n kube-system -l name=sealed-secrets-controller | grep -q Running; then
    print_error "Sealed Secrets Controller が動作していません。先に導入してください。"
    exit 1
fi

print_info "Sealed Secrets作成を開始します..."

# 一時ディレクトリ作成
TMP_DIR=$(mktemp -d)
SEALED_DIR="../sealed-secrets"

mkdir -p "$SEALED_DIR"

# 1. Slack Secret
print_info "Slack Secret を作成中..."
read -sp "Slack Bot Token を入力してください: " SLACK_TOKEN
echo

kubectl create secret generic slack-secret \
  --namespace=sandbox \
  --from-literal=token="$SLACK_TOKEN" \
  --dry-run=client -o yaml > "$TMP_DIR/slack-secret.yaml"

kubeseal -f "$TMP_DIR/slack-secret.yaml" -w "$SEALED_DIR/slack-sealed.yaml"
print_success "slack-sealed.yaml を作成しました"

# 2. Harbor Secret
print_info "Harbor Secret を作成中..."
read -p "Harbor Username を入力してください: " HARBOR_USERNAME
read -sp "Harbor Password を入力してください: " HARBOR_PASSWORD
echo

kubectl create secret docker-registry harbor-secret \
  --namespace=sandbox \
  --docker-server="REPLACE_WITH_HARBOR_URL" \
  --docker-username="$HARBOR_USERNAME" \
  --docker-password="$HARBOR_PASSWORD" \
  --dry-run=client -o yaml > "$TMP_DIR/harbor-secret.yaml"

kubeseal -f "$TMP_DIR/harbor-secret.yaml" -w "$SEALED_DIR/harbor-sealed.yaml"
print_success "harbor-sealed.yaml を作成しました"

# 3. GitHub Runner Secret
print_info "GitHub Runner Secret を作成中..."
read -sp "GitHub Runner Token を入力してください: " GITHUB_TOKEN
echo

kubectl create secret generic github-runner-token \
  --namespace=github-runners \
  --from-literal=token="$GITHUB_TOKEN" \
  --dry-run=client -o yaml > "$TMP_DIR/github-runner-secret.yaml"

kubeseal -f "$TMP_DIR/github-runner-secret.yaml" -w "$SEALED_DIR/github-runner-sealed.yaml"
print_success "github-runner-sealed.yaml を作成しました"

# 一時ファイル削除
rm -rf "$TMP_DIR"

print_info "kustomization.yaml を更新中..."
cat > "$SEALED_DIR/../kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- sealed-secrets/slack-sealed.yaml
- sealed-secrets/harbor-sealed.yaml
- sealed-secrets/github-runner-sealed.yaml

namespace: default
EOF

print_success "すべてのSealed Secretsが作成されました！"
print_info "次のコマンドでクラスターに適用してください:"
echo "kubectl apply -k secrets/"

print_warning "注意: 平文のSecretファイルは作成されていません。安全に管理されています。"