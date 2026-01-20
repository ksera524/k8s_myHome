#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/common-logging.sh" ]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/common-logging.sh"
else
  log_status() { echo "$@"; }
  log_warning() { echo "$@"; }
  log_error() { echo "$@"; }
fi

if [ -f "$SCRIPT_DIR/settings-loader.sh" ]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/settings-loader.sh" load 2>/dev/null || true
fi

CONTROL_PLANE_IP="${K8S_CONTROL_PLANE_IP:-192.168.122.10}"
K8S_USER="${K8S_USER:-k8suser}"

ssh_cmd=(ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR "${K8S_USER}@${CONTROL_PLANE_IP}")

log_status "=== Phase 5: Verify ==="

log_status "ArgoCDリフレッシュ中..."
"${ssh_cmd[@]}" 'kubectl get application platform -n argocd >/dev/null 2>&1 && kubectl annotate application platform -n argocd argocd.argoproj.io/refresh=hard --overwrite' || true
"${ssh_cmd[@]}" 'kubectl get application user-applications -n argocd >/dev/null 2>&1 && kubectl annotate application user-applications -n argocd argocd.argoproj.io/refresh=hard --overwrite' || true
sleep 5

log_status "Cloudflaredアプリ確認中..."
if "${ssh_cmd[@]}" 'kubectl get application cloudflared -n argocd >/dev/null 2>&1'; then
  log_status "✓ CloudflaredはArgoCD管理です"
else
  log_warning "Cloudflaredは未検出です（同期待機中の可能性）"
fi

log_status "ArgoCDアプリ一覧:"
"${ssh_cmd[@]}" 'kubectl get applications -n argocd --no-headers' | awk '{print "  - " $1 " (" $2 "/" $3 ")"}' || true
