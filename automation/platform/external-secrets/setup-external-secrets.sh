#!/bin/bash

# External Secrets Operator セットアップスクリプト
# k8s_myHome用の段階的導入自動化

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

# 現在のディレクトリを確認
if [[ ! -d "../../infra/external-secrets" ]]; then
    print_error "infra/external-secrets ディレクトリが見つかりません"
    print_error "automation/platform/external-secrets から実行してください"
    exit 1
fi

print_status "=== External Secrets Operator セットアップ開始 ==="

# Phase 1: App-of-Apps更新確認
print_status "Phase 1: ArgoCD Application設定確認"

APP_OF_APPS_FILE="../../infra/app-of-apps.yaml"
if grep -q "external-secrets-operator" "$APP_OF_APPS_FILE"; then
    print_debug "external-secrets-operator はすでにapp-of-apps.yamlに登録済み"
else
    print_warning "app-of-apps.yamlにexternal-secrets-operatorを追加する必要があります"
    print_debug "手動で以下を $APP_OF_APPS_FILE に追加してください："
    cat << 'EOF'
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-secrets-operator
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/ksera524/k8s_myHome.git
    targetRevision: HEAD
    path: infra/external-secrets
    directory:
      include: "external-secrets-operator-app.yaml"
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
fi

# Phase 2: ArgoCD Application同期待機
print_status "Phase 2: ArgoCD Application同期待機"

print_debug "ArgoCD Applicationの作成を待機中..."
timeout=300
while [ $timeout -gt 0 ]; do
    if kubectl get application external-secrets-operator -n argocd >/dev/null 2>&1; then
        print_status "✓ ArgoCD Application作成確認"
        break
    fi
    echo "ArgoCD Application作成待機中... (残り ${timeout}秒)"
    sleep 10
    timeout=$((timeout - 10))
done

if [ $timeout -le 0 ]; then
    print_error "ArgoCD Application作成がタイムアウトしました"
    print_error "手動でapp-of-apps.yamlの更新とArgoCD同期を確認してください"
    exit 1
fi

# Phase 3: ESO Pod起動待機
print_status "Phase 3: External Secrets Operator Pod起動待機"

print_debug "ESO Controller Pod起動を待機中..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=external-secrets \
    -n external-secrets-system \
    --timeout=300s

if [ $? -eq 0 ]; then
    print_status "✓ External Secrets Operator起動完了"
else
    print_error "External Secrets Operator起動に失敗しました"
    print_debug "ESO Pod状態:"
    kubectl get pods -n external-secrets-system
    exit 1
fi

# Phase 4: CRD確認
print_status "Phase 4: Custom Resource Definition確認"

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

# Phase 5: 基本動作確認
print_status "Phase 5: 基本動作確認"

print_debug "ESO Controller バージョン確認:"
kubectl get deployment external-secrets -n external-secrets-system \
    -o jsonpath='{.spec.template.spec.containers[0].image}'
echo ""

print_debug "ESO Controller ログ確認（最新10行）:"
kubectl logs -n external-secrets-system deployment/external-secrets --tail=10

# Phase 6: 次のステップ案内
print_status "Phase 6: セットアップ完了"

cat << EOF

${GREEN}✅ External Secrets Operatorセットアップ完了${NC}

${YELLOW}次のステップ:${NC}
1. Pulumi ESC認証設定:
   ${BLUE}./setup-pulumi-esc-auth.sh${NC}

2. SecretStore設定:
   ${BLUE}kubectl apply -f secretstores/pulumi-esc-secretstore.yaml${NC}

3. Harbor Secret移行:
   ${BLUE}kubectl apply -f externalsecrets/harbor-externalsecret.yaml${NC}

${YELLOW}確認コマンド:${NC}
- ESO状態確認: ${BLUE}kubectl get pods -n external-secrets-system${NC}
- CRD確認: ${BLUE}kubectl get crd | grep external-secrets${NC}
- Application確認: ${BLUE}kubectl get applications -n argocd | grep external-secrets${NC}

EOF

print_status "=== セットアップ完了 ==="