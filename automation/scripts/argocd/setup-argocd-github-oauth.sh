#!/bin/bash

# ArgoCD GitHub OAuth設定スクリプト (GitOps + External Secret統合版)

set -euo pipefail

# スクリプトディレクトリ取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 共通色設定スクリプトを読み込み
source "$SCRIPT_DIR/../common-colors.sh"

print_status "=== ArgoCD GitHub OAuth 最終統合確認 ==="

# SSH known_hosts クリーンアップ
print_debug "SSH known_hosts をクリーンアップ中..."
ssh-keygen -f "$HOME/.ssh/known_hosts" -R '192.168.122.10' 2>/dev/null || true

# k8sクラスタ接続確認
print_debug "k8sクラスタ接続を確認中..."
if ! ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=10 k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
    print_error "k8sクラスタに接続できません"
    exit 1
fi

print_status "ArgoCD GitHub OAuth統合状態を確認中..."

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
echo "=== External Secret状態確認 ==="

# ArgoCD GitHub OAuth External Secret状態確認
if kubectl get externalsecret argocd-github-oauth-secret -n argocd >/dev/null 2>&1; then
    ES_STATUS=$(kubectl get externalsecret argocd-github-oauth-secret -n argocd -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    echo "ArgoCD GitHub OAuth External Secret: $ES_STATUS"
    
    if [ "$ES_STATUS" != "True" ]; then
        echo "⚠️ External Secret準備中または失敗中"
        echo "詳細状態:"
        kubectl describe externalsecret argocd-github-oauth-secret -n argocd || true
    else
        echo "✅ External Secret準備完了"
    fi
else
    echo "❌ ArgoCD GitHub OAuth External Secretが見つかりません"
fi

echo -e "\n=== argocd-secret状態確認 ==="

if kubectl get secret argocd-secret -n argocd >/dev/null 2>&1; then
    echo "✅ argocd-secret存在"
    
    # Client ID確認
    CLIENT_ID_CURRENT=$(kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.dex\.github\.clientId}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    if [[ -n "$CLIENT_ID_CURRENT" ]]; then
        echo "✅ Client ID設定済み: ${CLIENT_ID_CURRENT:0:8}..."
    else
        echo "❌ Client ID未設定"
    fi
    
    # Client Secret確認
    if kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.dex\.github\.clientSecret}' >/dev/null 2>&1; then
        CLIENT_SECRET_LENGTH=$(kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.dex\.github\.clientSecret}' | base64 -d | wc -c)
        if [ "$CLIENT_SECRET_LENGTH" -gt 10 ]; then
            echo "✅ Client Secret設定済み (長さ: $CLIENT_SECRET_LENGTH 文字)"
        else
            echo "❌ Client Secret短すぎる (長さ: $CLIENT_SECRET_LENGTH 文字)"
        fi
    else
        echo "❌ Client Secret未設定"
    fi
else
    echo "❌ argocd-secret不存在"
fi

echo -e "\n=== ArgoCD設定状態確認 ==="

# ArgoCD ConfigMap確認
if kubectl get configmap argocd-cm -n argocd -o yaml | grep -q "dex.config"; then
    echo "✅ ArgoCD ConfigMapにDex設定存在"
    if kubectl get configmap argocd-cm -n argocd -o yaml | grep -q "github"; then
        echo "✅ GitHub OAuth設定存在"
    else
        echo "❌ GitHub OAuth設定不存在"
    fi
else
    echo "❌ ArgoCD ConfigMapにDex設定不存在"
fi

# ArgoCD Pod状態確認
ARGOCD_SERVER_READY=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server --no-headers | grep -c Running || echo "0")
ARGOCD_DEX_READY=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-dex-server --no-headers | grep -c Running || echo "0")

echo "ArgoCD Server Pods Ready: $ARGOCD_SERVER_READY"
echo "ArgoCD Dex Pods Ready: $ARGOCD_DEX_READY"

# 問題があれば修正を試行
if kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.dex\.github\.clientSecret}' >/dev/null 2>&1; then
    CLIENT_SECRET_LENGTH=$(kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.dex\.github\.clientSecret}' | base64 -d | wc -c)
    if [ "$CLIENT_SECRET_LENGTH" -lt 10 ]; then
        echo "🔧 Client Secret問題を修正中..."
        
        # External Secret から再同期を強制
        if kubectl get externalsecret argocd-github-oauth-secret -n argocd >/dev/null 2>&1; then
            echo "External Secret再同期を実行中..."
            kubectl annotate externalsecret argocd-github-oauth-secret -n argocd force-sync="$(date +%s)" --overwrite
            
            # 少し待機
            sleep 5
            
            # 再確認
            if kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.dex\.github\.clientSecret}' >/dev/null 2>&1; then
                NEW_CLIENT_SECRET_LENGTH=$(kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.dex\.github\.clientSecret}' | base64 -d | wc -c)
                if [ "$NEW_CLIENT_SECRET_LENGTH" -gt 10 ]; then
                    echo "✅ Client Secret修正完了 (長さ: $NEW_CLIENT_SECRET_LENGTH 文字)"
                    
                    # ArgoCD再起動
                    echo "ArgoCD再起動を実行中..."
                    kubectl rollout restart deployment argocd-server -n argocd >/dev/null 2>&1
                    kubectl rollout restart deployment argocd-dex-server -n argocd >/dev/null 2>&1
                    echo "✅ ArgoCD再起動完了"
                else
                    echo "❌ Client Secret修正失敗"
                fi
            else
                echo "❌ Client Secret再同期失敗"
            fi
        else
            echo "❌ External Secret見つからず、修正不可"
        fi
    fi
else
    echo "❌ Client Secret不存在、修正試行中..."
    
    # External Secret再同期
    if kubectl get externalsecret argocd-github-oauth-secret -n argocd >/dev/null 2>&1; then
        echo "External Secret強制再同期中..."
        kubectl annotate externalsecret argocd-github-oauth-secret -n argocd force-sync="$(date +%s)" --overwrite
        sleep 5
    fi
fi

echo -e "\n=== 最終確認結果 ==="
if kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.dex\.github\.clientSecret}' >/dev/null 2>&1; then
    FINAL_CLIENT_SECRET_LENGTH=$(kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.dex\.github\.clientSecret}' | base64 -d | wc -c)
    if [ "$FINAL_CLIENT_SECRET_LENGTH" -gt 10 ]; then
        echo "✅ GitHub OAuth設定正常 - Login可能"
    else
        echo "❌ GitHub OAuth設定異常 - Login失敗の可能性"
    fi
else
    echo "❌ GitHub OAuth設定異常 - Client Secret不存在"
fi
EOF

print_status "=== ArgoCD GitHub OAuth確認完了 ==="

echo ""
echo "🔧 GitHub OAuth設定状況:"
echo "- Client ID: ESO/設定ファイル経由で管理"
echo "- Client Secret: External Secret自動管理"
echo "- 設定方式: GitOps + External Secret直接統合"
echo ""
echo "🌐 アクセス方法:"
echo "- ArgoCD UI: https://argocd.qroksera.com"
echo "- 「LOG IN VIA GITHUB」でGitHub認証"
echo ""
echo "⚠️  まだLogin failedが発生する場合:"
echo "1. 数分待ってからもう一度試してください"
echo "2. ArgoCD Podの再起動を手動実行してください"
echo "3. External Secretの同期状態を確認してください"