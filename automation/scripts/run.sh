#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOMATION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="$AUTOMATION_DIR/run.log"

# 共通ログ出力
if [ -f "$SCRIPT_DIR/common-logging.sh" ]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/common-logging.sh"
else
  log_status() { echo "$@"; }
  log_error() { echo "$@"; }
fi

run_step() {
  local name="$1"
  shift
  log_status "=== ${name} ==="
  {
    "$@"
  } 2>&1 | tee -a "$LOG_FILE"
  return ${PIPESTATUS[0]}
}

ensure_sudo() {
  if ! sudo -v; then
    log_error "sudo権限の取得に失敗しました"
    exit 1
  fi
}

with_settings() {
  if [ -f "$SCRIPT_DIR/settings-loader.sh" ] && [ -f "$AUTOMATION_DIR/settings.toml" ]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/settings-loader.sh" load 2>/dev/null || true
  fi
  "$@"
}

usage() {
  cat << 'USAGE'
Usage: ./scripts/run.sh <phase>

Phases:
  all                 - 1〜5を順番に実行
  phase1|vm           - VMの構成（host-setup）
  phase2|k8s          - k8sの構成（infrastructure）
  phase3|gitops-prep  - ESOなどGitOps準備（platform）
  phase4|gitops-apps  - GitOpsによるアプリ展開（app-deploy）
  phase5|verify       - 確認（verify）
  upgrade             - k8sアップグレード（完全自動）
  upgrade-precheck    - アップグレード事前チェック
  upgrade-control-plane - コントロールプレーン更新
  upgrade-workers     - ワーカーノード更新
  upgrade-postcheck   - アップグレード後チェック

Log:
  automation/run.log
USAGE
}

main() {
  local phase="${1:-all}"

  log_status "ログ: $LOG_FILE"
  log_status "開始: $(date '+%Y-%m-%d %H:%M:%S')"

  case "$phase" in
    all)
      ensure_sudo
      run_step "Phase 1: VM" with_settings bash -c "cd \"$AUTOMATION_DIR/host-setup\" && ./setup-host.sh"
      run_step "Phase 2: k8s" with_settings bash -c "cd \"$AUTOMATION_DIR/infrastructure\" && ./clean-and-deploy.sh"
      run_step "Phase 3: GitOps Prep" with_settings bash -c "cd \"$AUTOMATION_DIR/platform\" && ./platform-deploy.sh"
      run_step "Phase 4: GitOps Apps" with_settings "$SCRIPT_DIR/app-deploy.sh"
      run_step "Phase 5: Verify" with_settings "$SCRIPT_DIR/verify.sh"
      ;;
    phase1|vm)
      ensure_sudo
      run_step "Phase 1: VM" with_settings bash -c "cd \"$AUTOMATION_DIR/host-setup\" && ./setup-host.sh"
      ;;
    phase2|k8s)
      run_step "Phase 2: k8s" with_settings bash -c "cd \"$AUTOMATION_DIR/infrastructure\" && ./clean-and-deploy.sh"
      ;;
    phase3|gitops-prep)
      run_step "Phase 3: GitOps Prep" with_settings bash -c "cd \"$AUTOMATION_DIR/platform\" && ./platform-deploy.sh"
      ;;
    phase4|gitops-apps)
      run_step "Phase 4: GitOps Apps" with_settings "$SCRIPT_DIR/app-deploy.sh"
      ;;
    phase5|verify)
      run_step "Phase 5: Verify" with_settings "$SCRIPT_DIR/verify.sh"
      ;;
    upgrade)
      run_step "Upgrade: Precheck" with_settings "$SCRIPT_DIR/upgrade/upgrade-precheck.sh"
      run_step "Upgrade: Control Plane" with_settings "$SCRIPT_DIR/upgrade/upgrade-control-plane.sh"
      run_step "Upgrade: Workers" with_settings "$SCRIPT_DIR/upgrade/upgrade-workers.sh"
      run_step "Upgrade: Postcheck" with_settings "$SCRIPT_DIR/upgrade/upgrade-postcheck.sh"
      ;;
    upgrade-precheck)
      run_step "Upgrade: Precheck" with_settings "$SCRIPT_DIR/upgrade/upgrade-precheck.sh"
      ;;
    upgrade-control-plane)
      run_step "Upgrade: Control Plane" with_settings "$SCRIPT_DIR/upgrade/upgrade-control-plane.sh"
      ;;
    upgrade-workers)
      run_step "Upgrade: Workers" with_settings "$SCRIPT_DIR/upgrade/upgrade-workers.sh"
      ;;
    upgrade-postcheck)
      run_step "Upgrade: Postcheck" with_settings "$SCRIPT_DIR/upgrade/upgrade-postcheck.sh"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      log_error "不明なフェーズ: $phase"
      usage
      exit 1
      ;;
  esac
}

main "$@"
