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

if [[ -f "$ROOT_DIR/manifests/infrastructure/gitops/harbor/kustomization.yaml" ]] \
  && grep -q -E '^\s*-\s*node-mutations/' "$ROOT_DIR/manifests/infrastructure/gitops/harbor/kustomization.yaml"; then
  check_ng "harbor 既定 kustomization に node-mutations が含まれています"
else
  check_ok "harbor のノード改変リソースは既定で無効です"
fi

cluster_contract="$ROOT_DIR/manifests/contracts/home-lab/cluster-contract.yaml"
access_contract="$ROOT_DIR/manifests/contracts/home-lab/access-surfaces.yaml"

if [[ -f "$cluster_contract" ]] && [[ -f "$access_contract" ]]; then
  check_ok "home-lab contract ファイルが存在します"
else
  check_ng "home-lab contract ファイルが不足しています"
fi

if [[ -f "$cluster_contract" ]]; then
  for required_key in \
    'external: qroksera.com' \
    'internal: internal.qroksera.com' \
    'gateway: 192.168.122.100' \
    'tailscaleSplitDNS: 192.168.122.101' \
    'external: nfs-external'; do
    if ! grep -q "$required_key" "$cluster_contract"; then
      check_ng "cluster-contract に必須値がありません: $required_key"
    fi
  done
fi

if [[ -f "$access_contract" ]]; then
  for surface_id in \
    argocd-external \
    argocd-internal \
    harbor-external \
    harbor-internal \
    rustfs-console \
    blog-external \
    cooklog-internal \
    api-hub-internal \
    hitomi-upload-viewer-internal; do
    if ! grep -q "^    ${surface_id}:" "$access_contract"; then
      check_ng "access-surfaces に surface ID がありません: $surface_id"
    fi
  done

  for surface_id in \
    argocd-external \
    argocd-internal \
    harbor-external \
    harbor-internal \
    rustfs-console \
    blog-external \
    cooklog-internal \
    api-hub-internal \
    hitomi-upload-viewer-internal; do
    if ! grep -R -q "contracts.k8s-myhome.local/access-surface: ${surface_id}" "$ROOT_DIR/manifests/access"; then
      check_ng "access manifest に contract surface annotation がありません: $surface_id"
    fi
  done
fi

if ! grep -q 'contracts.k8s-myhome.local/service-ip: network.serviceIPs.gateway' \
  "$ROOT_DIR/manifests/access/dns/core/coredns-configmap.yaml"; then
  check_ng "CoreDNS host override が cluster contract gateway service IP を参照していません"
fi

if ! grep -q 'contracts.k8s-myhome.local/service-ip: network.serviceIPs.tailscaleSplitDNS' \
  "$ROOT_DIR/manifests/access/dns/tailscale/manifest.yaml"; then
  check_ng "Tailscale Split DNS Service が cluster contract service IP を参照していません"
fi

if ! grep -q 'contracts.k8s-myhome.local/cloudflared-tunnel-id: shared.cloudflared.tunnelId' \
  "$ROOT_DIR/manifests/access/cloudflared/cloudflared-config.yaml"; then
  check_ng "Cloudflared config が access contract tunnel ID を参照していません"
fi

external_secrets_dir="$ROOT_DIR/manifests/platform/secrets/external-secrets"

for secret_domain in stores argocd harbor github-actions networking app-runtime; do
  if [[ -f "$external_secrets_dir/$secret_domain/kustomization.yaml" ]]; then
    check_ok "ExternalSecret domain が存在します: $secret_domain"
  else
    check_ng "ExternalSecret domain が不足しています: $secret_domain"
  fi
done

if [[ -f "$external_secrets_dir/external-secret-resources.yaml" ]]; then
  check_ng "ExternalSecret monolith が残っています: external-secret-resources.yaml"
fi

if grep -R -n '^kind: ExternalSecret$' "$ROOT_DIR/manifests/platform/argocd-config" >/dev/null 2>&1; then
  check_ng "pre-ESO path に top-level ExternalSecret が残っています"
  grep -R -n '^kind: ExternalSecret$' "$ROOT_DIR/manifests/platform/argocd-config" || true
else
  check_ok "pre-ESO path に top-level ExternalSecret はありません"
fi

legacy_secret_checks=(
  "harbor""-auth-secret"
  "github""-auth-secret"
  "harbor""-registry-secret"
  "grafana-cloud-credentials"
  "grafana-cloud-monitoring"
  "promtail-grafana-cloud-config"
)

for legacy_secret in "${legacy_secret_checks[@]}"; do
  if grep -R -n "$legacy_secret" "$external_secrets_dir" >/dev/null 2>&1; then
    check_ng "target-state ExternalSecret 配下に legacy secret が残っています: $legacy_secret"
  fi
done

for expected_secret in \
  harbor-admin-secret \
  harbor-registry-sandbox \
  github-multi-repo-secret \
  cloudflared-secret \
  cloudflare-api-token \
  tailscale-oauth \
  slack-secret \
  rustfs-auth-rustfs \
  rustfs-auth-sandbox; do
  if ! grep -R -q "${expected_secret}.yaml" "$external_secrets_dir"; then
    check_ng "ExternalSecret split 後の expected file が参照されていません: $expected_secret"
  fi
done

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
