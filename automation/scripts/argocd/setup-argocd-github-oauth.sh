#!/bin/bash
# ArgoCD GitHub OAuth Setup Script

set -euo pipefail

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIGINAL_SCRIPT_DIR="${SCRIPT_DIR}"
AUTOMATION_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 共通関数の読み込み
source "${SCRIPT_DIR}/../common-logging.sh"
source "${SCRIPT_DIR}/../settings-loader.sh"
source "${ORIGINAL_SCRIPT_DIR}/github-auth-utils.sh"

# 設定ファイル読み込み
load_settings "${AUTOMATION_DIR}/settings.toml"

log_status "ArgoCD GitHub OAuth設定開始..."

CONTROL_PLANE_IP="192.168.122.10"

# ArgoCD namespace確認
if ! ssh -o StrictHostKeyChecking=no -o BatchMode=yes k8suser@${CONTROL_PLANE_IP} "kubectl get namespace argocd" &>/dev/null; then
    log_error "ArgoCD namespaceが存在しません"
    exit 1
fi

# GitHub OAuth設定の適用
if [[ -n "${GITHUB_OAUTH_CLIENT_ID:-}" ]] && [[ -n "${GITHUB_OAUTH_CLIENT_SECRET:-}" ]]; then
    log_status "GitHub OAuth認証情報設定中..."
    
    ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << EOF
# ArgoCD secretにOAuth設定を追加
kubectl patch secret argocd-secret -n argocd --type='json' -p='[
  {"op": "add", "path": "/data/dex.github.clientId", "value": "'$(echo -n ${GITHUB_OAUTH_CLIENT_ID} | base64 -w0)'"},
  {"op": "add", "path": "/data/dex.github.clientSecret", "value": "'$(echo -n ${GITHUB_OAUTH_CLIENT_SECRET} | base64 -w0)'"}
]' || kubectl create secret generic argocd-secret -n argocd \
  --from-literal=dex.github.clientId="${GITHUB_OAUTH_CLIENT_ID}" \
  --from-literal=dex.github.clientSecret="${GITHUB_OAUTH_CLIENT_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -

# ArgoCD server再起動
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout restart deployment argocd-dex-server -n argocd
EOF
    
    log_success "GitHub OAuth設定完了"
else
    log_warning "GitHub OAuth認証情報が設定されていません"
fi

# 設定確認
check_github_oauth_config "${CONTROL_PLANE_IP}"

log_success "ArgoCD GitHub OAuth設定完了"