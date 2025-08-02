#!/bin/bash

# ArgoCD GitHub OAuth設定自動修復スクリプト
# make all後にGitHub OAuth設定が消失した場合の自動修復

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

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

print_status "=== ArgoCD GitHub OAuth自動修復スクリプト ==="

# k8sクラスタ接続確認
print_debug "k8sクラスタ接続を確認中..."
if ! ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=10 k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
    print_error "k8sクラスタに接続できません"
    exit 1
fi

# ArgoCD ConfigMapのGitHub OAuth設定確認
print_debug "ArgoCD ConfigMapのGitHub OAuth設定を確認中..."

GITHUB_CONFIG_EXISTS=$(ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 '
    kubectl get configmap argocd-cm -n argocd -o jsonpath="{.data.dex\.config}" 2>/dev/null | grep -c "github" || echo "0"
')

URL_CONFIG_EXISTS=$(ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 '
    kubectl get configmap argocd-cm -n argocd -o jsonpath="{.data.url}" 2>/dev/null | grep -c "argocd.qroksera.com" || echo "0"
')

if [ "$GITHUB_CONFIG_EXISTS" -eq 0 ] || [ "$URL_CONFIG_EXISTS" -eq 0 ]; then
    print_warning "GitHub OAuth設定が不完全です。修復中..."
    
    # ConfigMapファイルをクラスタに転送
    ARGOCD_CONFIG_FILE="$PROJECT_ROOT/manifests/infrastructure/argocd/argocd-config.yaml"
    
    if [ ! -f "$ARGOCD_CONFIG_FILE" ]; then
        print_error "ArgoCD ConfigMapファイルが見つかりません: $ARGOCD_CONFIG_FILE"
        exit 1
    fi
    
    print_debug "ConfigMapファイルを転送中: $ARGOCD_CONFIG_FILE"
    scp "$ARGOCD_CONFIG_FILE" k8suser@192.168.122.10:~/argocd-config-repair.yaml
    
    # ConfigMapを適用
    print_debug "ArgoCD ConfigMapを適用中..."
    ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 '
        kubectl apply -f ~/argocd-config-repair.yaml
        if [ $? -eq 0 ]; then
            echo "✅ ArgoCD ConfigMap適用成功"
            
            # ArgoCD Server再起動
            echo "🔄 ArgoCD Server再起動中..."
            kubectl rollout restart deployment argocd-server -n argocd
            
            # 少し待機
            sleep 10
            
            # 設定確認
            GITHUB_CHECK=$(kubectl get configmap argocd-cm -n argocd -o jsonpath="{.data.dex\.config}" 2>/dev/null | grep -c "github" || echo "0")
            URL_CHECK=$(kubectl get configmap argocd-cm -n argocd -o jsonpath="{.data.url}" 2>/dev/null | grep -c "argocd.qroksera.com" || echo "0")
            
            if [ "$GITHUB_CHECK" -gt 0 ] && [ "$URL_CHECK" -gt 0 ]; then
                echo "✅ GitHub OAuth設定修復完了"
            else
                echo "❌ GitHub OAuth設定修復失敗"
                exit 1
            fi
        else
            echo "❌ ArgoCD ConfigMap適用失敗"
            exit 1
        fi
        
        # 一時ファイル削除
        rm -f ~/argocd-config-repair.yaml
    '
    
    print_status "GitHub OAuth設定が正常に修復されました"
else
    print_status "GitHub OAuth設定は正常です"
fi

print_status "=== 修復スクリプト完了 ==="