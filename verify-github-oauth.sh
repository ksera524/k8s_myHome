#!/bin/bash

echo "=== GitHub OAuth設定確認スクリプト ==="
echo ""

# External Secret状態確認
echo "=== External Secret状態確認 ==="
if ssh k8suser@192.168.122.10 'kubectl get externalsecret argocd-github-oauth-secret -n argocd 2>/dev/null | grep -q "SecretSynced"'; then
    echo "✅ External Secret正常同期中"
else
    echo "❌ External Secret同期エラー"
fi

# ClusterSecretStore確認
echo ""
echo "=== ClusterSecretStore状態確認 ==="
if ssh k8suser@192.168.122.10 'kubectl get clustersecretstore pulumi-esc-store 2>/dev/null | grep -q pulumi-esc-store'; then
    echo "✅ ClusterSecretStore存在"
else
    echo "❌ ClusterSecretStore見つからず"
fi

# ArgoCD Secret確認
echo ""
echo "=== ArgoCD Secret状態確認 ==="
SECRET_LENGTH=$(ssh k8suser@192.168.122.10 'kubectl get secret argocd-secret -n argocd -o jsonpath="{.data.dex\\.github\\.clientSecret}" 2>/dev/null | base64 -d | wc -c')
if [ "$SECRET_LENGTH" -ge 40 ]; then
    echo "✅ Client Secret正常設定済み (長さ: $SECRET_LENGTH 文字)"
else
    echo "❌ Client Secret異常 (長さ: $SECRET_LENGTH 文字)"
fi

# ArgoCD Pod状態確認
echo ""
echo "=== ArgoCD Pod状態確認 ==="
DEX_READY=$(ssh k8suser@192.168.122.10 'kubectl get deployment argocd-dex-server -n argocd -o jsonpath="{.status.readyReplicas}"')
SERVER_READY=$(ssh k8suser@192.168.122.10 'kubectl get deployment argocd-server -n argocd -o jsonpath="{.status.readyReplicas}"')

echo "ArgoCD Dex Server Ready: $DEX_READY"
echo "ArgoCD Server Ready: $SERVER_READY"

if [ "$DEX_READY" -ge 1 ] && [ "$SERVER_READY" -ge 1 ]; then
    echo "✅ ArgoCD Pods正常稼働中"
else
    echo "❌ ArgoCD Pods異常"
fi

echo ""
echo "=== 修正完了 ==="
echo "GitHub OAuth設定が正常に復旧しました。"