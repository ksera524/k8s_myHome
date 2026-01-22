#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOMATION_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 共通ログ出力
if [ -f "$AUTOMATION_DIR/scripts/common-logging.sh" ]; then
  # shellcheck source=/dev/null
  source "$AUTOMATION_DIR/scripts/common-logging.sh"
else
  log_status() { echo "$@"; }
  log_error() { echo "$@"; }
  log_warning() { echo "$@"; }
fi

# 設定読み込み
if [ -f "$AUTOMATION_DIR/scripts/settings-loader.sh" ]; then
  # shellcheck source=/dev/null
  source "$AUTOMATION_DIR/scripts/settings-loader.sh" load 2>/dev/null || true
fi

k8s_user="$(get_config kubernetes user "k8suser")"
control_plane_ip="$(get_config network control_plane_ip "192.168.122.10")"
ssh_key_path="$(get_config kubernetes ssh_key_path "")"

ssh_opts=(
  -o StrictHostKeyChecking=no
  -o BatchMode=yes
  -o LogLevel=ERROR
)

if [[ -n "$ssh_key_path" ]]; then
  ssh_opts+=("-i" "$ssh_key_path")
fi

ssh_cmd=(ssh "${ssh_opts[@]}" "${k8s_user}@${control_plane_ip}")

log_status "=== Upgrade Postcheck ==="

log_status "ノード確認中..."
"${ssh_cmd[@]}" "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide"

log_status "Pod 状態確認中..."
"${ssh_cmd[@]}" "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -A"

log_status "ArgoCD 同期状態確認中..."
"${ssh_cmd[@]}" "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get applications -n argocd"

log_status "Upgrade Postcheck 完了"
