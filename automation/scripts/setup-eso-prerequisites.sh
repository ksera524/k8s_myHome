#!/bin/bash
# ESO Prerequisites Setup Script

set -euo pipefail

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOMATION_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 共通関数の読み込み
source "${SCRIPT_DIR}/common-logging.sh"
source "${SCRIPT_DIR}/settings-loader.sh"

# 設定ファイル読み込み
load_settings "${AUTOMATION_DIR}/settings.toml"

# Kubernetes接続確認
CONTROL_PLANE_IP="192.168.122.10"

log_status "ESO Prerequisites設定中..."

# SSH経由でコマンド実行
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << 'PRE_EOF'
set -e

# External Secrets namespace作成
kubectl create namespace external-secrets-system --dry-run=client -o yaml | kubectl apply -f -

echo "ESO Prerequisites設定完了"
PRE_EOF

# Pulumi Access Token Secret作成（設定から読み込み）
if [[ -n "${PULUMI_ACCESS_TOKEN:-}" ]]; then
    log_status "Pulumi Access Token Secret作成中..."
    ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << EOF
kubectl create secret generic pulumi-esc-token \
  --namespace external-secrets-system \
  --from-literal=accessToken="${PULUMI_ACCESS_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -
EOF
    log_success "Pulumi Access Token Secret作成完了"
fi

log_success "ESO Prerequisites設定完了"