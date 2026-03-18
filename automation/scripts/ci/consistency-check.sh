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

if grep -R -n -E 'targetRevision:\s*main\b' "$ROOT_DIR/manifests/bootstrap" >/dev/null 2>&1; then
  check_ng "manifests/bootstrap に targetRevision: main が残っています"
  grep -R -n -E 'targetRevision:\s*main\b' "$ROOT_DIR/manifests/bootstrap" || true
else
  check_ok "targetRevision は HEAD に統一されています"
fi

if [[ -f "$ROOT_DIR/manifests/core/kustomization.yaml" ]]; then
  check_ok "manifests/core/kustomization.yaml が存在します"
else
  check_ng "manifests/core/kustomization.yaml が見つかりません"
fi

if grep -q 'storage-classes/local-storage-class.yaml' "$ROOT_DIR/manifests/core/kustomization.yaml" \
  && grep -q 'storage-classes/local-ssd-storage-class.yaml' "$ROOT_DIR/manifests/core/kustomization.yaml"; then
  check_ok "core kustomization に StorageClass リソースが含まれます"
else
  check_ng "core kustomization に StorageClass リソース定義が不足しています"
fi

if [[ -f "$ROOT_DIR/docs/diagrams/app-of-apps-sync-wave.md" ]] \
  && grep -q 'docs/diagrams/app-of-apps-sync-wave.md' "$ROOT_DIR/README.md"; then
  check_ok "README の構成図リンク先が存在します"
else
  check_ng "README の構成図リンクが不正です"
fi

if grep -q -E '^\s*-\s*node-mutations/' "$ROOT_DIR/manifests/infrastructure/gitops/harbor/kustomization.yaml"; then
  check_ng "harbor 既定 kustomization に node-mutations が含まれています"
else
  check_ok "harbor のノード改変リソースは既定で無効です"
fi

if [[ "$check_failed" -ne 0 ]]; then
  exit 1
fi
