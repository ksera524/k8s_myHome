#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

log_section() {
  echo ""
  echo "== $1 =="
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "${command_name} not found" >&2
    exit 1
  fi
}

log_section "Shellcheck"
require_command shellcheck

mapfile -t sh_files < <(find "$ROOT_DIR/automation" -name '*.sh' -print)
if ((${#sh_files[@]})); then
  shellcheck -S error -x "${sh_files[@]}"
else
  echo "No shell scripts found under automation/"
fi

log_section "Yamllint"
require_command yamllint

mapfile -t yaml_files < <(
  find \
    "$ROOT_DIR/manifests" \
    "$ROOT_DIR/automation/templates" \
    "$ROOT_DIR/automation/infrastructure" \
    -path '*/charts/*' -prune -o \
    \( -name '*.yaml' -o -name '*.yml' \) -print
)
if ((${#yaml_files[@]})); then
  yamllint -f parsable -c "$ROOT_DIR/.yamllint.yml" "${yaml_files[@]}"
else
  echo "No YAML files found for yamllint"
fi

require_command kustomize
require_command python3
if ! python3 -c 'import yaml' >/dev/null 2>&1; then
  echo "python3 PyYAML not found" >&2
  exit 1
fi

log_section "Policy checks"
"$ROOT_DIR/automation/scripts/ci/policy-check.sh"

log_section "Kubeconform"
require_command kubeconform

kubeconform_schema_locations=(
  -schema-location default
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{ .Group }}/{{ .ResourceKind }}_{{ .ResourceAPIVersion }}.json'
)

while IFS= read -r kfile; do
  kdir="$(dirname "$kfile")"
  echo "kustomize build --enable-helm $kdir | kubeconform"
  kustomize build --enable-helm "$kdir" \
    | kubeconform \
      -strict \
      -ignore-missing-schemas \
      "${kubeconform_schema_locations[@]}"
done < <(find "$ROOT_DIR/manifests" -name kustomization.yaml -print)

log_section "Consistency checks"
"$ROOT_DIR/automation/scripts/ci/consistency-check.sh"
