#!/bin/bash

# ESO Webhook問題の根本的解決スクリプト
# ValidatingWebhookConfigurationを無効化してArgoCD互換性を確保

set -euo pipefail

# 色設定
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

log_status "=== ESO Webhook 根本的修正スクリプト ==="
log_warning "このスクリプトはESO ValidatingWebhookを無効化します（開発環境用）"
echo

# k8sクラスタ接続確認
log_status "k8sクラスタ接続確認中..."
if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
    log_error "k8sクラスタに接続できません"
    exit 1
fi

# 現状確認
log_status "現在のESO Webhook状態を確認中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
echo "=== ValidatingWebhookConfigurations ==="
kubectl get validatingwebhookconfigurations | grep -E "external|secret"

echo ""
echo "=== ESO Pods状態 ==="
kubectl get pods -n external-secrets-system
EOF

# 修正処理実行確認
echo
read -p "ESO ValidatingWebhookを無効化しますか？ (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_warning "処理をキャンセルしました"
    exit 0
fi

# 修正処理
log_status "ESO Webhook無効化処理を開始..."

ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
set -e

echo "=== Step 1: ValidatingWebhookConfigurationを削除 ==="
# ESO関連のValidatingWebhookConfigurationを削除
kubectl delete validatingwebhookconfiguration externalsecret-validate --ignore-not-found=true
kubectl delete validatingwebhookconfiguration secretstore-validate --ignore-not-found=true

echo "✓ ValidatingWebhookConfiguration削除完了"

echo "=== Step 2: ESO Operator再起動 ==="
# ESO Operatorを再起動してWebhook無効化を反映
kubectl rollout restart deployment -n external-secrets-system external-secrets-operator
kubectl rollout restart deployment -n external-secrets-system external-secrets-operator-webhook
kubectl rollout restart deployment -n external-secrets-system external-secrets-operator-cert-controller

# 再起動待機
echo "Pod再起動待機中..."
sleep 10
kubectl wait --namespace external-secrets-system --for=condition=ready pod --selector=app.kubernetes.io/instance=external-secrets-operator --timeout=120s

echo "=== Step 3: ClusterSecretStore作成（必要に応じて） ==="
# ClusterSecretStoreが存在しない場合は作成
if ! kubectl get clustersecretstore pulumi-esc-store 2>/dev/null; then
    if kubectl get secret pulumi-esc-token -n external-secrets-system 2>/dev/null; then
        echo "ClusterSecretStoreを作成中..."
        cat <<'SECRETSTORE_EOF' | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: pulumi-esc-store
spec:
  provider:
    pulumi:
      apiUrl: https://api.pulumi.com/api/esc
      organization: ksera
      project: k8s
      environment: secret
      accessToken:
        secretRef:
          name: pulumi-esc-token
          namespace: external-secrets-system
          key: accessToken
SECRETSTORE_EOF
        echo "✓ ClusterSecretStore作成完了"
    else
        echo "❌ Pulumi Access Token未設定のためClusterSecretStoreを作成できません"
    fi
else
    echo "✓ ClusterSecretStore既に存在"
fi

echo "=== Step 4: Platform Application再同期 ==="
# Platform Applicationを強制同期
kubectl patch application platform -n argocd --type merge -p '{"operation": {"sync": {"syncStrategy": {"apply": {"force": true}}}}}' || true
echo "Platform Application同期開始..."
sleep 10

echo "=== 修正結果確認 ==="
echo "ValidatingWebhookConfigurations:"
kubectl get validatingwebhookconfigurations | grep -E "external|secret" || echo "✓ ESO ValidatingWebhook削除済み"

echo ""
echo "ClusterSecretStore状態:"
kubectl get clustersecretstore 2>/dev/null || echo "ClusterSecretStore未作成"

echo ""
echo "Platform Application状態:"
kubectl get application platform -n argocd | tail -1

echo ""
echo "External Secrets状態:"
kubectl get externalsecrets -A 2>/dev/null | head -5 || echo "External Secrets未作成"

echo "✓ ESO Webhook無効化処理完了"
EOF

log_status "=== ESO Webhook修正完了 ==="
log_status "ValidatingWebhookを無効化しました"
log_warning "注意: 本番環境では適切な証明書管理（cert-manager等）を検討してください"