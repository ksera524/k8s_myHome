#!/bin/bash

# ArgoCD GitHub OAuth設定スクリプト

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

print_status "=== ArgoCD GitHub OAuth設定開始 ==="

# 0. マニフェストファイルの準備
print_status "マニフェストファイルをリモートにコピー中..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scp -o StrictHostKeyChecking=no "$SCRIPT_DIR/manifests/argocd-github-oauth-secret.yaml" k8suser@192.168.122.10:/tmp/
scp -o StrictHostKeyChecking=no "$SCRIPT_DIR/manifests/argocd-cm-github-oauth.yaml" k8suser@192.168.122.10:/tmp/
scp -o StrictHostKeyChecking=no "$SCRIPT_DIR/manifests/argocd-rbac-cm-github.yaml" k8suser@192.168.122.10:/tmp/
print_status "✓ マニフェストファイルコピー完了"

# 1. 前提条件確認
print_status "前提条件を確認中..."

# SSH known_hosts クリーンアップ
print_debug "SSH known_hosts をクリーンアップ中..."
ssh-keygen -f "$HOME/.ssh/known_hosts" -R '192.168.122.10' 2>/dev/null || true

# k8sクラスタ接続確認
print_debug "k8sクラスタ接続を確認中..."
if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
    print_error "k8sクラスタに接続できません"
    exit 1
fi

# ArgoCD namespace確認
if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get namespace argocd' >/dev/null 2>&1; then
    print_error "argocd namespaceが見つかりません"
    print_error "先にArgoCDをデプロイしてください"
    exit 1
fi

# External Secrets Operator確認
ESO_READY=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get pods -n external-secrets-system --no-headers 2>/dev/null | grep -c Running' 2>/dev/null || echo "0")
if [[ "$ESO_READY" -eq 0 ]]; then
    print_error "External Secrets Operatorが稼働していません"
    exit 1
fi

# ClusterSecretStore確認
if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get clustersecretstore pulumi-esc-store' >/dev/null 2>&1; then
    print_error "ClusterSecretStore 'pulumi-esc-store' が見つかりません"
    exit 1
fi

print_status "✓ 前提条件確認完了"

# 2. GitHub OAuth ExternalSecret作成
print_status "GitHub OAuth ExternalSecretを作成中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
# ExternalSecretを適用
kubectl apply -f /tmp/argocd-github-oauth-secret.yaml

echo "ExternalSecretの同期を待機中..."
timeout=60
while [ $timeout -gt 0 ]; do
    if kubectl get secret argocd-github-oauth -n argocd >/dev/null 2>&1; then
        echo "✓ GitHub OAuth Secret同期完了"
        break
    fi
    
    # ExternalSecretの状態確認
    EXTERNALSECRET_STATUS=$(kubectl get externalsecret argocd-github-oauth-secret -n argocd -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    if [ "$EXTERNALSECRET_STATUS" = "False" ]; then
        ERROR_MESSAGE=$(kubectl get externalsecret argocd-github-oauth-secret -n argocd -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "Unknown")
        echo "ExternalSecret エラー: $ERROR_MESSAGE"
        exit 1
    fi
    
    echo "GitHub OAuth Secret同期待機中... (残り ${timeout}秒)"
    sleep 5
    timeout=$((timeout - 5))
done

if [ $timeout -le 0 ]; then
    echo "GitHub OAuth Secret同期がタイムアウトしました"
    exit 1
fi
EOF

print_status "✓ GitHub OAuth ExternalSecret作成完了"

# 3. ArgoCD ConfigMap更新
print_status "ArgoCD ConfigMapを更新中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
# 既存のConfigMapをバックアップ
kubectl get configmap argocd-cm -n argocd -o yaml > /tmp/argocd-cm-backup.yaml

# 新しいConfigMapを適用
kubectl apply -f /tmp/argocd-cm-github-oauth.yaml

echo "✓ ArgoCD ConfigMap更新完了"
EOF

# 4. ArgoCD RBAC ConfigMap更新
print_status "ArgoCD RBAC ConfigMapを更新中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
# 既存のRBAC ConfigMapをバックアップ
kubectl get configmap argocd-rbac-cm -n argocd -o yaml > /tmp/argocd-rbac-cm-backup.yaml 2>/dev/null || echo "RBAC ConfigMapが存在しません"

# 新しいRBAC ConfigMapを適用
kubectl apply -f /tmp/argocd-rbac-cm-github.yaml

echo "✓ ArgoCD RBAC ConfigMap更新完了"
EOF

# 5. ArgoCD サーバー再起動
print_status "ArgoCD サーバーを再起動中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
# ArgoCD サーバーを再起動
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout restart deployment argocd-dex-server -n argocd

# 再起動完了を待機
kubectl rollout status deployment argocd-server -n argocd --timeout=300s
kubectl rollout status deployment argocd-dex-server -n argocd --timeout=300s

echo "✓ ArgoCD サーバー再起動完了"
EOF

print_status "✓ ArgoCD サーバー再起動完了"

# 6. 設定確認
print_status "ArgoCD GitHub OAuth設定を確認中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
echo "=== ArgoCD Pods状態 ==="
kubectl get pods -n argocd

echo -e "\n=== GitHub OAuth Secret確認 ==="
if kubectl get secret argocd-github-oauth -n argocd >/dev/null 2>&1; then
    echo "✓ argocd-github-oauth Secret存在"
    echo "Secret keys:"
    kubectl get secret argocd-github-oauth -n argocd -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null || echo "取得失敗"
else
    echo "❌ argocd-github-oauth Secret不存在"
fi

echo -e "\n=== ArgoCD ConfigMap確認 ==="
if kubectl get configmap argocd-cm -n argocd -o yaml | grep -q "dex.config"; then
    echo "✓ GitHub OAuth設定が含まれています"
else
    echo "⚠️ GitHub OAuth設定が見つかりません"
fi

echo -e "\n=== ArgoCD RBAC ConfigMap確認 ==="
if kubectl get configmap argocd-rbac-cm -n argocd >/dev/null 2>&1; then
    echo "✓ RBAC ConfigMap存在"
else
    echo "⚠️ RBAC ConfigMapが見つかりません"
fi
EOF

print_status "=== ArgoCD GitHub OAuth設定完了 ==="

echo ""
echo "✅ 設定完了:"
echo "1. GitHub OAuth ExternalSecret作成済み"
echo "2. ArgoCD ConfigMapにGitHub OAuth設定追加"
echo "3. ArgoCD RBAC ConfigMapでGitHub認証権限設定"
echo "4. ArgoCD サーバー再起動完了"
echo ""
echo "📝 GitHub OAuth設定:"
echo "- Client ID: Ov23li8T6IFuiuLcoSJa"
echo "- Client Secret: Pulumi ESCのargoCDキーから自動取得"
echo "- Callback URL: https://argocd.qroksera.com/api/dex/callback"
echo ""
echo "🔧 GitHubアプリケーション設定確認事項:"
echo "1. GitHub OAuth App設定でCallback URLを確認"
echo "2. Organization設定でThird-party accessを有効化"
echo "3. argocd-rbac-cm-github.yamlのorg/team名を実際の値に更新"
echo ""
echo "🌐 アクセス方法:"
echo "1. ArgoCD UI: https://argocd.qroksera.com"
echo "2. 「LOG IN VIA GITHUB」ボタンでGitHub認証"
echo "3. 初回ログイン時にGitHub認可画面が表示される"
echo ""
echo "⚠️ 注意事項:"
echo "- argocd-rbac-cm-github.yamlのGitHubユーザー名/組織名を実際の値に更新してください"
echo "- ドメイン設定がargocd.qroksera.com以外の場合、設定を修正してください"