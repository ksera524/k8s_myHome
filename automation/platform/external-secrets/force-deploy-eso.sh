#!/bin/bash

# External Secrets Operator 強制デプロイスクリプト
# ArgoCD経由での自動デプロイが失敗した場合の緊急対応用

set -euo pipefail

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

print_status "=== External Secrets Operator 強制デプロイ ==="

# ArgoCD Application状態確認
print_debug "ArgoCD Application状態確認中..."
kubectl get applications -n argocd | grep -E "(infrastructure|external-secrets)" || true

print_debug "infrastructure application詳細確認中..."
kubectl describe application infrastructure -n argocd | tail -20

# infrastructure application強制同期
print_status "infrastructure application強制同期を実行中..."
kubectl patch application infrastructure -n argocd --type merge -p '{"operation":{"sync":{"force":true,"prune":true}}}'

# 同期待機
timeout=180
while [ $timeout -gt 0 ]; do
    if kubectl get application external-secrets-operator -n argocd >/dev/null 2>&1; then
        print_status "✓ external-secrets-operator Application作成完了"
        break
    fi
    echo "external-secrets-operator Application作成待機中... (残り ${timeout}秒)"
    sleep 10
    timeout=$((timeout - 10))
done

if [ $timeout -le 0 ]; then
    print_error "external-secrets-operator Application作成に失敗しました"
    
    # Helm直接インストールにフォールバック
    print_warning "Helm直接インストールにフォールバック中..."
    
    # external-secrets-system namespace作成
    kubectl create namespace external-secrets-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Helm repo追加とインストール
    helm repo add external-secrets https://charts.external-secrets.io
    helm repo update
    
    # Helm values設定
    cat > /tmp/external-secrets-values.yaml << 'EOF'
installCRDs: true
replicaCount: 1

resources:
  limits:
    cpu: 100m
    memory: 128Mi
  requests:
    cpu: 10m
    memory: 32Mi

serviceMonitor:
  enabled: true
  additionalLabels:
    release: prometheus

webhook:
  replicaCount: 1
  resources:
    limits:
      cpu: 100m
      memory: 128Mi
    requests:
      cpu: 10m
      memory: 32Mi

certController:
  replicaCount: 1
  resources:
    limits:
      cpu: 100m
      memory: 128Mi
    requests:
      cpu: 10m
      memory: 32Mi

securityContext:
  runAsNonRoot: true
  runAsUser: 65534

env:
  LOG_LEVEL: info
EOF
    
    # Helmインストール
    helm upgrade --install external-secrets external-secrets/external-secrets \
        --namespace external-secrets-system \
        --values /tmp/external-secrets-values.yaml \
        --version 0.18.2
    
    # クリーンアップ
    rm -f /tmp/external-secrets-values.yaml
    
    print_status "✓ Helm直接インストール完了"
else
    # external-secrets-operator Application同期
    print_status "external-secrets-operator Application同期中..."
    kubectl patch application external-secrets-operator -n argocd --type merge -p '{"operation":{"sync":{"force":true}}}'
fi

# Pod起動待機
print_status "External Secrets Operator Pod起動待機中..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=external-secrets \
    -n external-secrets-system \
    --timeout=300s

# 結果確認
print_status "=== デプロイ結果確認 ==="
echo "Deployments:"
kubectl get deployments -n external-secrets-system

echo ""
echo "Pods:"
kubectl get pods -n external-secrets-system

echo ""
echo "CRDs:"
kubectl get crd | grep external-secrets

print_status "✅ External Secrets Operator強制デプロイ完了"