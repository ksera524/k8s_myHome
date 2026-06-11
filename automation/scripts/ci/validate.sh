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

log_section "Kustomize build"
if ! command -v kustomize >/dev/null 2>&1; then
  echo "kustomize not found" >&2
  exit 1
fi

while IFS= read -r kfile; do
  kdir="$(dirname "$kfile")"
  echo "kustomize build --enable-helm $kdir"
  kustomize build --enable-helm "$kdir" >/dev/null

done < <(find "$ROOT_DIR/manifests" -name kustomization.yaml -print)

log_section "Policy checks"
"$ROOT_DIR/automation/scripts/ci/policy-check.sh"

log_section "Kubeconform"
if ! command -v kubeconform >/dev/null 2>&1; then
  echo "kubeconform not found" >&2
  exit 1
fi

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
