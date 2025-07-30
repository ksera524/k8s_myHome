#!/bin/bash

# External Secrets Operator Helmインストール → ArgoCD移行スクリプト
# k8s_myHome用の段階的導入

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

print_status "=== External Secrets Operator Helm → ArgoCD移行 ==="

# Phase 1: Helmリポジトリ追加・更新
print_status "Phase 1: Helmリポジトリ設定"

helm repo add external-secrets https://charts.external-secrets.io
helm repo update

print_debug "Helmリポジトリ追加完了"

# Phase 2: Helm values.yaml作成
print_status "Phase 2: Helm values設定ファイル作成"

cat > /tmp/eso-values.yaml << 'EOF'
# k8s_myHome最適化設定
installCRDs: true
replicaCount: 1

# リソース制限（ホームラボ環境）
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
EOF

print_debug "Helm values.yaml作成: /tmp/eso-values.yaml"

# Phase 3: Helmでインストール
print_status "Phase 3: External Secrets Operator Helmインストール"

helm install external-secrets external-secrets/external-secrets \
  -n external-secrets-system \
  --create-namespace \
  --values /tmp/eso-values.yaml \
  --version 0.18.2

if [ $? -eq 0 ]; then
    print_status "✓ External Secrets Operator Helmインストール完了"
else
    print_error "External Secrets Operator Helmインストールに失敗しました"
    exit 1
fi

# Phase 4: Pod起動待機
print_status "Phase 4: Pod起動確認"

print_debug "ESO Controller Pod起動を待機中..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=external-secrets \
    -n external-secrets-system \
    --timeout=300s

if [ $? -eq 0 ]; then
    print_status "✓ External Secrets Operator Pod起動完了"
else
    print_error "Pod起動に失敗しました"
    kubectl get pods -n external-secrets-system
    exit 1
fi

# Phase 5: CRD確認
print_status "Phase 5: Custom Resource Definition確認"

REQUIRED_CRDS=(
    "externalsecrets.external-secrets.io"
    "secretstores.external-secrets.io"
    "clustersecretstores.external-secrets.io"
)

for crd in "${REQUIRED_CRDS[@]}"; do
    if kubectl get crd "$crd" >/dev/null 2>&1; then
        print_status "✓ CRD確認: $crd"
    else
        print_error "✗ CRD未確認: $crd"
        exit 1
    fi
done

# Phase 6: ArgoCD Application準備
print_status "Phase 6: ArgoCD移行準備"

# Helm values.yamlを永続化場所にコピー
cp /tmp/eso-values.yaml ../../../manifests/external-secrets/operator-values.yaml

print_debug "Helm values.yamlを manifests/external-secrets/operator-values.yaml にコピー"

# ArgoCD Application用のvalues参照版を作成
cat > ../../../manifests/external-secrets/external-secrets-operator-app.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-secrets-operator
  namespace: argocd
  annotations:
    # Helmで直接インストールから移行済み
    argocd.argoproj.io/sync-options: Replace=true
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: 'https://charts.external-secrets.io'
    targetRevision: '0.18.2'
    chart: external-secrets
    helm:
      valueFiles:
      - $values/manifests/external-secrets/operator-values.yaml
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: external-secrets-system
  syncPolicy:
    syncOptions:
      - Replace=true
      - Force=true
    # 最初は手動同期でテスト
    # automated:
    #   prune: true
    #   selfHeal: true
  ignoreDifferences:
  - group: apiextensions.k8s.io
    kind: CustomResourceDefinition
    jqPathExpressions:
    - '.spec.conversion.webhook.clientConfig.caBundle'
EOF

print_debug "ArgoCD Application定義作成: manifests/external-secrets/external-secrets-operator-app.yaml"

# Phase 7: 動作確認
print_status "Phase 7: 動作確認"

print_debug "ESO Controller バージョン確認:"
ESO_VERSION=$(kubectl get deployment external-secrets -n external-secrets-system \
    -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "ESO Image: $ESO_VERSION"

print_debug "インストール済みリソース確認:"
kubectl get all -n external-secrets-system

print_debug "Helm Release確認:"
helm list -n external-secrets-system

# Phase 8: 次のステップ案内
print_status "Phase 8: Helmインストール完了"

cat << EOF

${GREEN}✅ External Secrets Operator Helmインストール完了${NC}

${YELLOW}現在の状態:${NC}
- ESO Pod: Running
- CRD: インストール済み
- Helm Release: external-secrets (external-secrets-system)

${YELLOW}ArgoCD移行手順:${NC}

1. ${BLUE}ArgoCD Application作成${NC}:
   ${BLUE}kubectl apply -f ../../../manifests/external-secrets/external-secrets-operator-app.yaml${NC}

2. ${BLUE}App-of-Apps更新${NC} (manifests/app-of-apps.yamlに追加):
   ${BLUE}---
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: external-secrets-app
     namespace: argocd
   spec:
     source:
       repoURL: https://github.com/ksera524/k8s_myHome.git
       targetRevision: HEAD
       path: manifests/external-secrets
       directory:
         include: "external-secrets-operator-app.yaml"${NC}

3. ${BLUE}ArgoCD同期確認${NC}:
   ${BLUE}kubectl get applications -n argocd | grep external-secrets${NC}

4. ${BLUE}Helm Release削除${NC} (ArgoCD移行後):
   ${BLUE}helm uninstall external-secrets -n external-secrets-system${NC}

${YELLOW}次のステップ:${NC}
1. Pulumi ESC認証設定
2. SecretStore設定
3. Harbor Secret移行

${YELLOW}確認コマンド:${NC}
- ESO状態: ${BLUE}kubectl get pods -n external-secrets-system${NC}
- CRD確認: ${BLUE}kubectl get crd | grep external-secrets${NC}
- Helm確認: ${BLUE}helm list -n external-secrets-system${NC}

EOF

print_status "=== Helmインストール完了 ==="