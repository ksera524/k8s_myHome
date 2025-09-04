#!/bin/bash

# External Secrets Operator (ESO) 修正スクリプト
# ESO Webhook証明書問題を完全に解決

set -euo pipefail

# 色設定
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_status "=== External Secrets Operator 修正スクリプト ==="

# k8sクラスタ接続確認
print_status "k8sクラスタ接続確認中..."
if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
    print_error "k8sクラスタに接続できません"
    exit 1
fi

# ESOの状態確認
print_status "External Secrets Operatorの現在の状態:"
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
echo "=== ESO Pods ==="
kubectl get pods -n external-secrets-system

echo "=== ClusterSecretStore ==="
kubectl get clustersecretstore 2>/dev/null || echo "ClusterSecretStore未作成"

echo "=== Platform Application状態 ==="
kubectl get application platform -n argocd -o wide 2>/dev/null || echo "Platform Application未作成"
EOF

# 修正処理実行確認
read -p "ESOのWebhook証明書問題を修正しますか？ (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "修正をキャンセルしました"
    exit 0
fi

# 修正処理
print_status "External Secrets Operator修正処理を開始します..."

ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
set -e

echo "=== Step 1: ESO Webhook証明書の削除と再生成 ==="
# 既存のWebhook証明書を削除
kubectl delete secret external-secrets-operator-webhook-cert -n external-secrets-system --ignore-not-found=true

# Webhook関連のPodを再起動
echo "Webhook Podを再起動中..."
kubectl rollout restart deployment external-secrets-operator-webhook -n external-secrets-system
kubectl rollout restart deployment external-secrets-operator-cert-controller -n external-secrets-system
kubectl rollout restart deployment external-secrets-operator -n external-secrets-system

# 再起動を待機
echo "Pod再起動待機中..."
sleep 15
kubectl wait --namespace external-secrets-system --for=condition=ready pod --selector=app.kubernetes.io/instance=external-secrets-operator --timeout=120s

echo "=== Step 2: Webhook証明書の確認 ==="
for i in {1..30}; do
    if kubectl get secret external-secrets-operator-webhook-cert -n external-secrets-system 2>/dev/null; then
        echo "✓ Webhook証明書が作成されました"
        break
    fi
    echo "証明書作成待機中... ($i/30)"
    sleep 2
done

echo "=== Step 3: Platform Applicationの再同期 ==="
# Platform Application のfinalizers削除（必要に応じて）
kubectl patch application platform -n argocd --type merge -p '{"metadata": {"finalizers": null}}' 2>/dev/null || true

# 強制同期
echo "Platform Applicationを強制同期中..."
kubectl patch application platform -n argocd --type merge -p '{"operation": {"sync": {"syncStrategy": {"apply": {"force": true}}}}}' || true
sleep 10

echo "=== Step 4: ClusterSecretStoreの手動作成（必要に応じて） ==="
# Pulumi Token確認
if kubectl get secret pulumi-esc-token -n external-secrets-system 2>/dev/null; then
    echo "✓ Pulumi Access Token確認OK"
    
    # ClusterSecretStore作成
    if ! kubectl get clustersecretstore pulumi-esc-store 2>/dev/null; then
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
        echo "✓ ClusterSecretStore既に存在"
    fi
else
    echo "❌ Pulumi Access Token未設定"
    echo "automation/settings.tomlのPulumi.access_tokenを確認してください"
fi

echo "=== Step 5: External Secretsの再同期 ==="
# すべてのExternal Secretsをリスト
echo "External Secrets再同期中..."
kubectl get externalsecrets -A --no-headers | while read ns name rest; do
    kubectl annotate externalsecret "$name" -n "$ns" refresh=now --overwrite 2>/dev/null || true
done

echo "=== 修正完了確認 ==="
sleep 10

# 最終状態確認
echo "ESO Pods状態:"
kubectl get pods -n external-secrets-system

echo "ClusterSecretStore状態:"
kubectl get clustersecretstore 2>/dev/null || echo "ClusterSecretStore未作成"

echo "Platform Application状態:"
kubectl get application platform -n argocd -o wide 2>/dev/null || echo "Platform Application未作成"

echo "External Secrets状態:"
kubectl get externalsecrets -A 2>/dev/null | head -10 || echo "External Secrets未作成"

echo "✓ ESO修正処理完了"
EOF

print_status "=== External Secrets Operator修正完了 ==="
print_status "問題が続く場合は以下を確認してください:"
print_status "1. settings.tomlのPulumi.access_tokenが正しく設定されているか"
print_status "2. GitHub Personal Access Tokenが有効か"
print_status "3. ネットワーク接続に問題がないか"