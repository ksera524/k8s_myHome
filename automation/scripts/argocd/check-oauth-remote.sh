#!/bin/bash
# Remote execution script for ArgoCD OAuth check

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
    CLIENT_ID_CURRENT=$(kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.dex\.github\.clientId}' 2>/dev/null || echo "")
    if [[ -n "$CLIENT_ID_CURRENT" ]]; then
        CLIENT_ID_DECODED=$(echo "$CLIENT_ID_CURRENT" | base64 -d 2>/dev/null || echo "")
        if [[ -n "$CLIENT_ID_DECODED" ]]; then
            echo "✅ Client ID設定済み: ${CLIENT_ID_DECODED:0:8}..."
        else
            echo "❌ Client ID未設定"
        fi
    else
        echo "❌ Client ID未設定"
    fi
    
    # Client Secret確認
    CLIENT_SECRET_BASE64=$(kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.dex\.github\.clientSecret}' 2>/dev/null || echo "")
    if [[ -n "$CLIENT_SECRET_BASE64" ]]; then
        CLIENT_SECRET_DECODED=$(echo "$CLIENT_SECRET_BASE64" | base64 -d 2>/dev/null || echo "")
        CLIENT_SECRET_LENGTH=${#CLIENT_SECRET_DECODED}
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

echo -e "\n=== 最終確認結果 ==="
FINAL_CLIENT_SECRET_BASE64=$(kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.dex\.github\.clientSecret}' 2>/dev/null || echo "")
if [[ -n "$FINAL_CLIENT_SECRET_BASE64" ]]; then
    FINAL_CLIENT_SECRET_DECODED=$(echo "$FINAL_CLIENT_SECRET_BASE64" | base64 -d 2>/dev/null || echo "")
    FINAL_CLIENT_SECRET_LENGTH=${#FINAL_CLIENT_SECRET_DECODED}
    if [ "$FINAL_CLIENT_SECRET_LENGTH" -gt 10 ]; then
        echo "✅ GitHub OAuth設定正常 - Login可能"
    else
        echo "❌ GitHub OAuth設定異常 - Login失敗の可能性"
    fi
else
    echo "❌ GitHub OAuth設定異常 - Client Secret不存在"
fi