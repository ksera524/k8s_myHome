#!/bin/bash

# External Secrets Operator Helmデプロイスクリプト
# HelmでESO直接デプロイ → その後ArgoCD管理に移行

set -euo pipefail

# PATH設定
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# カラー設定
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

print_status "=== External Secrets Operator Helmデプロイ ==="

# 前提条件確認
print_status "前提条件を確認中..."

# 既存インストール確認
if kubectl get deployments -n external-secrets-system 2>/dev/null | grep -q external-secrets; then
    print_status "External Secrets Operator は既にインストール済みです"
    kubectl get pods -n external-secrets-system
    exit 0
fi

# 必要なnamespace存在確認
REQUIRED_NAMESPACES=("external-secrets-system" "harbor" "arc-systems")
for ns in "${REQUIRED_NAMESPACES[@]}"; do
    if ! kubectl get namespace "$ns" >/dev/null 2>&1; then
        print_debug "必要なnamespace $ns を作成中..."
        kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
        print_status "✓ namespace $ns 作成完了"
    else
        print_debug "✓ namespace $ns 確認済み"
    fi
done

# Pulumi Access Token Secret確認
PAT_MISSING_NAMESPACES=()
for ns in "${REQUIRED_NAMESPACES[@]}"; do
    if ! kubectl get secret pulumi-access-token -n "$ns" >/dev/null 2>&1; then
        PAT_MISSING_NAMESPACES+=("$ns")
    fi
done

if [ ${#PAT_MISSING_NAMESPACES[@]} -gt 0 ]; then
    print_warning "以下のnamespaceでPulumi Access Token Secretが見つかりませんでした: ${PAT_MISSING_NAMESPACES[*]}"
    if [ -n "${PULUMI_ACCESS_TOKEN:-}" ]; then
        print_debug "環境変数からPulumi Access Tokenを設定中..."
        for ns in "${PAT_MISSING_NAMESPACES[@]}"; do
            kubectl create secret generic pulumi-access-token \
                --from-literal=PULUMI_ACCESS_TOKEN="$PULUMI_ACCESS_TOKEN" \
                --namespace="$ns" \
                --dry-run=client -o yaml | kubectl apply -f -
            print_status "✓ pulumi-access-token Secret作成完了: $ns"
        done
    else
        print_warning "PULUMI_ACCESS_TOKEN環境変数が設定されていません"
        print_warning "External Secrets機能が制限される可能性があります"
    fi
fi

# Helmインストール確認
print_status "Helmインストール状況を確認中..."
if ! command -v helm >/dev/null 2>&1; then
    print_status "Helmをインストール中..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm -f get_helm.sh
    print_status "✓ Helmインストール完了"
else
    print_debug "✓ Helm確認済み: $(helm version --short)"
fi

# Helmリポジトリ設定
print_status "Helmリポジトリを設定中..."
if ! helm repo list | grep -q external-secrets; then
    helm repo add external-secrets https://charts.external-secrets.io
fi
helm repo update

# Helm values設定
print_status "Helm values設定を作成中..."
cat > /tmp/external-secrets-values.yaml << 'EOF'
# k8s_myHome環境用External Secrets Operator設定
installCRDs: true
replicaCount: 1

# リソース制限（ホームラボ環境最適化）
resources:
  limits:
    cpu: 100m
    memory: 128Mi
  requests:
    cpu: 10m
    memory: 32Mi

# Prometheus監視有効化
serviceMonitor:
  enabled: true
  additionalLabels:
    release: prometheus

# Webhook設定
webhook:
  replicaCount: 1
  resources:
    limits:
      cpu: 100m
      memory: 128Mi
    requests:
      cpu: 10m
      memory: 32Mi

# 証明書コントローラー設定
certController:
  replicaCount: 1
  resources:
    limits:
      cpu: 100m
      memory: 128Mi
    requests:
      cpu: 10m
      memory: 32Mi

# セキュリティ設定
securityContext:
  runAsNonRoot: true
  runAsUser: 65534

# ログレベル設定
env:
  LOG_LEVEL: info

# ArgoCD管理ラベル追加（後で移行用）
commonLabels:
  app.kubernetes.io/managed-by: "helm-to-argocd"
  argocd.argoproj.io/instance: "external-secrets-operator"
EOF

# HelmでExternal Secrets Operatorをインストール
print_status "HelmでExternal Secrets Operatorをインストール中..."
helm upgrade --install external-secrets external-secrets/external-secrets \
    --namespace external-secrets-system \
    --values /tmp/external-secrets-values.yaml \
    --version 0.18.2 \
    --wait \
    --timeout 300s

# クリーンアップ
rm -f /tmp/external-secrets-values.yaml

# Pod起動確認
print_status "Pod起動状態を確認中..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=external-secrets \
    -n external-secrets-system \
    --timeout=120s

# CRD確認
print_status "CRD確認中..."
REQUIRED_CRDS=(
    "externalsecrets.external-secrets.io"
    "secretstores.external-secrets.io"
    "clustersecretstores.external-secrets.io"
)

for crd in "${REQUIRED_CRDS[@]}"; do
    if kubectl get crd "$crd" >/dev/null 2>&1; then
        print_debug "✓ CRD確認: $crd"
    else
        print_error "✗ CRD未確認: $crd"
        exit 1
    fi
done

# ArgoCD管理に移行するためのアノテーション追加
print_status "ArgoCD管理移行用アノテーション追加中..."
kubectl annotate namespace external-secrets-system \
    argocd.argoproj.io/managed-by=external-secrets-operator \
    --overwrite

# Helmリリース情報をArgoCD用に設定
kubectl label namespace external-secrets-system \
    app.kubernetes.io/managed-by=argocd \
    app.kubernetes.io/instance=external-secrets-operator \
    --overwrite

print_status "=== デプロイ結果確認 ==="
echo "Deployments:"
kubectl get deployments -n external-secrets-system

echo ""
echo "Pods:"
kubectl get pods -n external-secrets-system

echo ""
echo "Services:"
kubectl get services -n external-secrets-system

echo ""
echo "CRDs:"
kubectl get crd | grep external-secrets

print_status "✅ External Secrets Operator Helmデプロイ完了"

cat << 'EOF'

🎯 次のステップ:
1. ArgoCD管理への移行:
   - infrastructure applicationの同期を実行
   - HelmリリースからArgoCD管理への自動移行

2. SecretStore設定:
   cd automation/platform/external-secrets
   kubectl apply -f secretstores/pulumi-esc-secretstore.yaml

3. Harbor Secrets設定:
   ./deploy-harbor-secrets.sh

📋 確認コマンド:
- ESO状態: kubectl get pods -n external-secrets-system
- CRD確認: kubectl get crd | grep external-secrets
- Helm確認: helm list -n external-secrets-system

EOF