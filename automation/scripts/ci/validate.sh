#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

log_section() {
  echo ""
  echo "== $1 =="
}

log_section "Shellcheck"
if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck not found" >&2
  exit 1
fi

mapfile -t sh_files < <(find "$ROOT_DIR/automation" -name '*.sh' -print)
if ((${#sh_files[@]})); then
  shellcheck -S error -x "${sh_files[@]}"
else
  echo "No shell scripts found under automation/"
fi

log_section "Yamllint"
if ! command -v yamllint >/dev/null 2>&1; then
  echo "yamllint not found" >&2
  exit 1
fi

yamllint -c "$ROOT_DIR/.yamllint.yml" \
  "$ROOT_DIR/manifests" \
  "$ROOT_DIR/automation/templates" \
  "$ROOT_DIR/automation/infrastructure"

log_section "Kustomize build"
if ! command -v kustomize >/dev/null 2>&1; then
  echo "kustomize not found" >&2
  exit 1
fi

while IFS= read -r kfile; do
  kdir="$(dirname "$kfile")"
  echo "kustomize build $kdir"
  kustomize build "$kdir" >/dev/null

done < <(find "$ROOT_DIR/manifests" -name kustomization.yaml -print)
