#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

check_failed=0

check_ok() {
  echo "[OK] $1"
}

check_ng() {
  echo "[NG] $1" >&2
  check_failed=1
}

if command -v python3 >/dev/null 2>&1; then
  if python3 -c 'import yaml' >/dev/null 2>&1; then
    if python3 "$ROOT_DIR/automation/scripts/ci/consistency-check.py"; then
      check_ok "YAML 構造ベースの整合性を確認しました"
    else
      check_ng "YAML 構造ベースの整合性チェックに失敗しました"
    fi
  else
    check_ng "python3 の PyYAML が見つかりません"
  fi
else
  check_ng "python3 が見つかりません"
fi

if [[ -f "$ROOT_DIR/docs/diagrams/app-of-apps-sync-wave.md" ]] \
  && grep -q 'docs/diagrams/app-of-apps-sync-wave.md' "$ROOT_DIR/README.md"; then
  check_ok "README の構成図リンク先が存在します"
else
  check_ng "README の構成図リンクが不正です"
fi

if command -v python3 >/dev/null 2>&1; then
  if python3 -c 'import yaml' >/dev/null 2>&1; then
    if "$ROOT_DIR/automation/scripts/ci/contract-check.py"; then
      check_ok "contract と access manifests の整合性を確認しました"
    else
      check_ng "contract と access manifests の整合性チェックに失敗しました"
    fi
  else
    check_ng "python3 の PyYAML が見つかりません"
  fi
else
  check_ng "python3 が見つかりません"
fi

if [[ "$check_failed" -ne 0 ]]; then
  exit 1
fi
