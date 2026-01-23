#!/bin/bash
# GitHub Actions Runner Controller (ARC) Setup Script

set -euo pipefail

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOMATION_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 共通関数の読み込み
source "${SCRIPT_DIR}/../common-logging.sh"
source "${SCRIPT_DIR}/../settings-loader.sh"

# 設定ファイル読み込み
load_settings "${AUTOMATION_DIR}/settings.toml"

log_status "GitHub Actions Runner Controller (ARC) セットアップ開始..."

CONTROL_PLANE_IP="192.168.122.10"

# ARC namespace作成
log_status "ARC namespace作成中..."
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << 'EOF'
kubectl create namespace arc-systems --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace arc-runners --dry-run=client -o yaml | kubectl apply -f -
EOF

# GitHub認証情報はExternal Secrets Operatorが管理するため、手動作成は不要
# External Secretsが自動的にgithub-authシークレットを作成・更新する

# Harbor認証情報Secret作成（ESO経由で取得）
log_status "Harbor認証情報Secret確認中..."
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << 'EOF'
# Harbor namespace/secretの起動待機
timeout=300
while [ $timeout -gt 0 ]; do
    if kubectl get namespace harbor >/dev/null 2>&1 && kubectl get secret harbor-admin-secret -n harbor >/dev/null 2>&1; then
        break
    fi
    echo "Harborリソース待機中... (残り ${timeout}s)"
    sleep 10
    timeout=$((timeout - 10))
done

if ! kubectl get secret harbor-admin-secret -n harbor >/dev/null 2>&1; then
    echo "エラー: Harbor secretの準備が完了していません"
    exit 1
fi

# ESOからHarborパスワードを取得
HARBOR_PASSWORD=$(kubectl get secret harbor-admin-secret -n harbor -o jsonpath='{.data.password}' | base64 -d)
if [[ -z "$HARBOR_PASSWORD" ]]; then
    echo "エラー: ESOからHarborパスワードを取得できませんでした"
    exit 1
fi

kubectl create secret generic harbor-auth \
  --namespace arc-systems \
  --from-literal=HARBOR_USERNAME="admin" \
  --from-literal=HARBOR_PASSWORD="${HARBOR_PASSWORD}" \
  --from-literal=HARBOR_URL="harbor.local" \
  --from-literal=HARBOR_PROJECT="sandbox" \
  --dry-run=client -o yaml | kubectl apply -f -
EOF

# GitHub Actions Runner用ServiceAccount作成
log_status "GitHub Actions Runner ServiceAccount作成中..."
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << 'EOF'
# ServiceAccount作成
kubectl create serviceaccount github-actions-runner \
  --namespace arc-systems \
  --dry-run=client -o yaml | kubectl apply -f -

# 権限設定（Secretアクセス用）
kubectl create rolebinding github-actions-runner-binding \
  --namespace arc-systems \
  --clusterrole=admin \
  --serviceaccount=arc-systems:github-actions-runner \
  --dry-run=client -o yaml | kubectl apply -f -

# ServiceAccount確認
if kubectl get serviceaccount github-actions-runner -n arc-systems >/dev/null 2>&1; then
    echo "✓ ServiceAccount github-actions-runner 作成完了"
else
    echo "❌ ServiceAccount作成失敗"
    exit 1
fi
EOF

# Helm確認・インストール
log_status "Helm確認中..."
if ! ssh -o StrictHostKeyChecking=no k8suser@${CONTROL_PLANE_IP} 'which helm' >/dev/null 2>&1; then
    log_status "Helmをインストール中..."
    ssh -o StrictHostKeyChecking=no k8suser@${CONTROL_PLANE_IP} 'curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash'
    log_status "✓ Helmインストール完了"
else
    log_debug "✓ Helm確認済み"
fi

# ARC Controller Helm chart インストール
log_status "ARC Controller Helm chart インストール中..."
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << 'EOF'
# Helm リポジトリ追加
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
helm repo update

# ARC Controller インストール
helm upgrade --install arc-controller \
  oci://ghcr.io/actions/gha-runner-scale-set-controller \
  --namespace arc-systems \
  --create-namespace \
  --wait
EOF

log_success "GitHub Actions Runner Controller (ARC) セットアップ完了"
