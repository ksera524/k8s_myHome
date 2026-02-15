#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOMATION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$AUTOMATION_DIR/.." && pwd)"

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
APP_OF_APPS_SRC="$ROOT_DIR/manifests/bootstrap/app-of-apps.yaml"
APP_OF_APPS_DST="/tmp/app-of-apps.yaml"

ssh_cmd=(ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR "${K8S_USER}@${CONTROL_PLANE_IP}")

log_status "=== Phase 4: GitOps Apps (App-of-Apps) ==="

if ! "${ssh_cmd[@]}" 'kubectl get namespace argocd' >/dev/null 2>&1; then
  log_error "ArgoCD namespaceが見つかりません。Phase3を先に実行してください。"
  exit 1
fi

if [ ! -f "$APP_OF_APPS_SRC" ]; then
  log_error "app-of-apps.yamlが見つかりません: $APP_OF_APPS_SRC"
  exit 1
fi

log_status "App-of-Appsマニフェストを転送中..."
scp -o StrictHostKeyChecking=no "$APP_OF_APPS_SRC" "${K8S_USER}@${CONTROL_PLANE_IP}:${APP_OF_APPS_DST}"

log_status "App-of-Appsを適用中..."
if "${ssh_cmd[@]}" "kubectl apply -f ${APP_OF_APPS_DST}"; then
  log_status "✓ App-of-Apps 適用完了"
  "${ssh_cmd[@]}" "kubectl get applications -n argocd --no-headers" | awk '{print "  - " $1 " (" $2 "/" $3 ")"}' || true
else
  log_warning "App-of-Apps適用で問題が発生しました"
  exit 1
fi
