#!/usr/bin/env bash

# GitOps bootstrap entrypoint.
# 責務は ArgoCD 初期導入、pre-ESO 最小 Secret、root Application 適用に限定する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOMATION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$AUTOMATION_DIR/.." && pwd)"

# shellcheck source=../scripts/common-logging.sh
source "$AUTOMATION_DIR/scripts/common-logging.sh"

if [[ -f "$AUTOMATION_DIR/scripts/settings-loader.sh" ]]; then
  # shellcheck source=../scripts/settings-loader.sh
  source "$AUTOMATION_DIR/scripts/settings-loader.sh" load 2>/dev/null || true
fi

CONTROL_PLANE_IP="${K8S_CONTROL_PLANE_IP:-192.168.122.10}"
K8S_USER="${K8S_USER:-k8suser}"
REMOTE_TMP="/tmp/k8s-myhome-bootstrap"
APP_OF_APPS_SRC="$ROOT_DIR/manifests/bootstrap/app-of-apps.yaml"
ARGOCD_INGRESS_SRC="$AUTOMATION_DIR/templates/platform/argocd-ingress.yaml"

ssh_cmd=(ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR "${K8S_USER}@${CONTROL_PLANE_IP}")
scp_cmd=(scp -o StrictHostKeyChecking=no -o LogLevel=ERROR)

require_file() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    log_error "必要なファイルが見つかりません: $file_path"
    exit 1
  fi
}

copy_manifest() {
  local src="$1"
  local dst_name="$2"
  "${scp_cmd[@]}" "$src" "${K8S_USER}@${CONTROL_PLANE_IP}:${REMOTE_TMP}/${dst_name}"
}

log_status "=== GitOps bootstrap 開始 ==="
log_status "対象 control-plane: ${K8S_USER}@${CONTROL_PLANE_IP}"

require_file "$APP_OF_APPS_SRC"
require_file "$ARGOCD_INGRESS_SRC"

if ! "${ssh_cmd[@]}" 'kubectl get nodes' >/dev/null 2>&1; then
  log_error "k8sクラスタに接続できません。make phase2 を先に完了してください。"
  exit 1
fi

if [[ -z "${PULUMI_ACCESS_TOKEN:-}" && -n "${PULUMI_PULUMI_ACCESS_TOKEN:-}" ]]; then
  PULUMI_ACCESS_TOKEN="$PULUMI_PULUMI_ACCESS_TOKEN"
  export PULUMI_ACCESS_TOKEN
fi

if [[ -z "${PULUMI_ACCESS_TOKEN:-}" ]]; then
  log_error "PULUMI_ACCESS_TOKEN が未設定です。automation/settings.toml または環境変数に設定してください。"
  exit 1
fi

"${ssh_cmd[@]}" "mkdir -p ${REMOTE_TMP}"
copy_manifest "$APP_OF_APPS_SRC" "app-of-apps.yaml"
copy_manifest "$ARGOCD_INGRESS_SRC" "argocd-ingress.yaml"

log_status "ArgoCD を初期導入中..."
"${ssh_cmd[@]}" <<'REMOTE'
set -euo pipefail

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.3.0/manifests/crds/applicationset-crd.yaml
kubectl get crd applicationsets.argoproj.io >/dev/null
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true"}}'
kubectl apply -f /tmp/k8s-myhome-bootstrap/argocd-ingress.yaml
REMOTE

log_status "pre-ESO Secret を作成中..."
pulumi_token_escaped="$(printf '%q' "$PULUMI_ACCESS_TOKEN")"
"${ssh_cmd[@]}" "PULUMI_ACCESS_TOKEN=${pulumi_token_escaped} bash -s" <<'REMOTE'
set -euo pipefail

kubectl create namespace external-secrets-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic pulumi-esc-token \
  --namespace external-secrets-system \
  --from-literal=accessToken="${PULUMI_ACCESS_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<'RBAC'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-secrets-kubernetes-provider
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["serviceaccounts"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["serviceaccounts/token"]
    verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-secrets-kubernetes-provider
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-secrets-kubernetes-provider
subjects:
  - kind: ServiceAccount
    name: external-secrets-operator
    namespace: external-secrets-system
RBAC
REMOTE

log_status "root Application を適用中..."
"${ssh_cmd[@]}" <<'REMOTE'
set -euo pipefail

kubectl apply -f /tmp/k8s-myhome-bootstrap/app-of-apps.yaml
kubectl get application bootstrap-root -n argocd >/dev/null
kubectl get applications -n argocd --no-headers 2>/dev/null | awk '{print "  - " $1 " (" $2 "/" $3 ")"}' || true
REMOTE

log_status "✓ GitOps bootstrap 完了"
log_status "以降の core / infrastructure / platform / access / apps 収束は ArgoCD child Application が管理します。"
