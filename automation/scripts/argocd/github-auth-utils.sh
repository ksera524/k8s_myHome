#!/bin/bash
# ArgoCD GitHub Auth Utils

set -euo pipefail

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOMATION_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 共通関数の読み込み
source "${SCRIPT_DIR}/../common-logging.sh"
source "${SCRIPT_DIR}/../settings-loader.sh"

# 設定ファイル読み込み
load_settings "${AUTOMATION_DIR}/settings.toml"

# GitHub OAuth設定の確認
check_github_oauth_config() {
    local control_plane_ip="${1:-192.168.122.10}"
    
    log_status "GitHub OAuth設定確認中..."
    
    # SSHで接続してOAuth設定を確認
    ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${control_plane_ip} << 'EOF'
# ArgoCD namespaceの確認
if ! kubectl get namespace argocd &>/dev/null; then
    echo "ERROR: ArgoCD namespace not found"
    exit 1
fi

# ArgoCD secretの確認
if kubectl get secret argocd-secret -n argocd &>/dev/null; then
    # Client IDとClient Secretの確認
    CLIENT_ID=$(kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.dex\.github\.clientId}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    CLIENT_SECRET=$(kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.dex\.github\.clientSecret}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    
    if [[ -n "${CLIENT_ID}" ]] && [[ -n "${CLIENT_SECRET}" ]]; then
        echo "GitHub OAuth設定確認: OK"
        echo "Client ID: ${CLIENT_ID:0:10}..."
        echo "Client Secret: [HIDDEN]"
    else
        echo "WARNING: GitHub OAuth設定が不完全です"
    fi
else
    echo "WARNING: ArgoCD secret not found"
fi
EOF
    
    log_success "GitHub OAuth設定確認完了"
}

# エクスポート
export -f check_github_oauth_config