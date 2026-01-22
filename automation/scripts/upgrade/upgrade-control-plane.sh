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

target_version="$(get_config upgrade target_version "")"
apt_channel="$(get_config upgrade apt_channel "")"
k8s_user="$(get_config kubernetes user "k8suser")"
control_plane_ip="$(get_config network control_plane_ip "192.168.122.10")"
ssh_key_path="$(get_config kubernetes ssh_key_path "")"

if [[ -z "$target_version" ]]; then
  log_error "upgrade.target_version が未設定です (例: v1.33.7)"
  exit 1
fi

target_minor="${target_version#v}"
target_minor="${target_minor%.*}"
if [[ -z "$apt_channel" ]]; then
  apt_channel="v${target_minor}"
fi

ssh_opts=(
  -o StrictHostKeyChecking=no
  -o BatchMode=yes
  -o LogLevel=ERROR
)

if [[ -n "$ssh_key_path" ]]; then
  ssh_opts+=("-i" "$ssh_key_path")
fi

ssh_cmd=(ssh "${ssh_opts[@]}" "${k8s_user}@${control_plane_ip}")

log_status "=== Upgrade Control Plane ==="
log_status "対象バージョン: ${target_version}"
log_status "APTチャネル: ${apt_channel}"

"${ssh_cmd[@]}" "sudo bash -c 'set -euo pipefail; echo deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${apt_channel}/deb/ / > /etc/apt/sources.list.d/kubernetes.list'"
"${ssh_cmd[@]}" "sudo apt-get update -y"

"${ssh_cmd[@]}" "sudo apt-mark unhold kubeadm kubelet kubectl"
"${ssh_cmd[@]}" "sudo bash -c 'set -euo pipefail; target=\"${target_version#v}\"; pkg=\"\"; while read -r _ version _; do if [[ \"$version\" == \"$target\"* ]]; then pkg=\"$version\"; break; fi; done < <(apt-cache madison kubeadm); if [[ -z \"$pkg\" ]]; then echo \"kubeadm ${target} が見つかりません\" >&2; exit 1; fi; apt-get install -y kubeadm=\"$pkg\"'"

log_status "kubeadm upgrade apply 実行中..."
"${ssh_cmd[@]}" "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubeadm upgrade apply ${target_version} -y"

"${ssh_cmd[@]}" "sudo bash -c 'set -euo pipefail; target=\"${target_version#v}\"; pkg=\"\"; while read -r _ version _; do if [[ \"$version\" == \"$target\"* ]]; then pkg=\"$version\"; break; fi; done < <(apt-cache madison kubelet); if [[ -z \"$pkg\" ]]; then echo \"kubelet ${target} が見つかりません\" >&2; exit 1; fi; apt-get install -y kubelet=\"$pkg\" kubectl=\"$pkg\"; systemctl daemon-reload; systemctl restart kubelet'"

log_status "Upgrade Control Plane 完了"
