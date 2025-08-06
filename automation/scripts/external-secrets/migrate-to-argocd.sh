#!/bin/bash

# External Secrets Operator: Helm → ArgoCD 管理移行スクリプト

set -euo pipefail

# スクリプトディレクトリ取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 共通色設定スクリプトを読み込み
source "$SCRIPT_DIR/../common-colors.sh"

print_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

print_status "=== External Secrets Operator: Helm → ArgoCD 管理移行 ==="

# 前提条件確認
print_status "前提条件確認中..."

# Helmリリースがインストールされているかチェック
if ! helm list -n external-secrets-system | grep -q external-secrets; then
    print_error "Helmリリース 'external-secrets' が見つかりません"
    print_error "先に helm-deploy-eso.sh を実行してください"
    exit 1
fi

# External Secrets OperatorのPodが稼働中かチェック
if ! kubectl get pods -n external-secrets-system | grep -q "external-secrets.*Running"; then
    print_error "External Secrets Operator のPodが稼働していません"
    exit 1
fi

# ArgoCD Application確認
if ! kubectl get application infrastructure -n argocd >/dev/null 2>&1; then
    print_error "ArgoCD infrastructure application が見つかりません"
    exit 1
fi

print_status "✓ 前提条件確認完了"

# ArgoCD infrastructure application同期
print_status "ArgoCD infrastructure application同期中..."
kubectl patch application infrastructure -n argocd --type merge -p '{"operation":{"sync":{"force":true}}}'

# external-secrets-operator Application作成待機
print_debug "external-secrets-operator Application作成待機中..."
timeout=120
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
    print_error "external-secrets-operator Application作成がタイムアウトしました"
    exit 1
fi

# ArgoCD管理への移行処理
print_status "ArgoCD管理への移行処理を開始..."

# 1. HelmリリースにArgoCD移行アノテーション追加
print_debug "Helmリリースアノテーション追加中..."
helm upgrade external-secrets external-secrets/external-secrets \
    --namespace external-secrets-system \
    --set-string "commonAnnotations.argocd\.argoproj\.io/sync-wave=1" \
    --set-string "commonAnnotations.meta\.helm\.sh/release-name=external-secrets" \
    --set-string "commonAnnotations.meta\.helm\.sh/release-namespace=external-secrets-system" \
    --reuse-values

# 2. ArgoCD Applicationの同期ポリシー更新
print_debug "ArgoCD Application同期ポリシー更新中..."
kubectl patch application external-secrets-operator -n argocd --type merge -p '{
    "spec": {
        "syncPolicy": {
            "automated": {
                "prune": false,
                "selfHeal": false
            },
            "syncOptions": [
                "CreateNamespace=true",
                "Replace=false"
            ]
        }
    }
}'

# 3. 段階的移行
print_status "段階的移行を開始..."

# 3.1. ArgoCD Applicationを一旦無効化して同期
print_debug "ArgoCD Application一時無効化..."
kubectl patch application external-secrets-operator -n argocd --type merge -p '{
    "spec": {
        "syncPolicy": {
            "automated": null
        }
    }
}'

# 3.2. 現在のリソース状態を保存
print_debug "現在のリソース状態保存中..."
kubectl get all -n external-secrets-system -o yaml > /tmp/eso-current-state.yaml

# 3.3. ArgoCD Applicationを手動同期（dry-run）
print_debug "ArgoCD Application dry-run 同期中..."
kubectl patch application external-secrets-operator -n argocd --type merge -p '{
    "operation": {
        "sync": {
            "dryRun": true,
            "force": false
        }
    }
}'

# 同期結果確認
sleep 10
SYNC_STATUS=$(kubectl get application external-secrets-operator -n argocd -o jsonpath='{.status.sync.status}')
HEALTH_STATUS=$(kubectl get application external-secrets-operator -n argocd -o jsonpath='{.status.health.status}')

print_debug "Dry-run結果: Sync=$SYNC_STATUS, Health=$HEALTH_STATUS"

# 3.4. 実際の同期実行
if [[ "$SYNC_STATUS" != "Unknown" ]]; then
    print_status "ArgoCD管理への最終移行実行中..."
    
    # Helmリリースを一旦 uninstall (リソースは保持)
    print_debug "Helmリリース削除（リソース保持）..."
    helm uninstall external-secrets -n external-secrets-system --keep-history
    
    # ArgoCD Applicationで管理開始
    print_debug "ArgoCD Application実同期実行..."
    kubectl patch application external-secrets-operator -n argocd --type merge -p '{
        "operation": {
            "sync": {
                "force": true,
                "prune": false
            }
        }
    }'
    
    # 同期完了待機
    timeout=180
    while [ $timeout -gt 0 ]; do
        SYNC_STATUS=$(kubectl get application external-secrets-operator -n argocd -o jsonpath='{.status.sync.status}')
        HEALTH_STATUS=$(kubectl get application external-secrets-operator -n argocd -o jsonpath='{.status.health.status}')
        
        if [[ "$SYNC_STATUS" == "Synced" && "$HEALTH_STATUS" == "Healthy" ]]; then
            print_status "✓ ArgoCD管理移行完了"
            break
        fi
        
        echo "ArgoCD同期待機中... (Sync: $SYNC_STATUS, Health: $HEALTH_STATUS, 残り ${timeout}秒)"
        sleep 15
        timeout=$((timeout - 15))
    done
    
    if [ $timeout -le 0 ]; then
        print_error "ArgoCD管理移行がタイムアウトしました"
        print_warning "手動確認が必要です:"
        print_debug "kubectl describe application external-secrets-operator -n argocd"
        exit 1
    fi
    
    # 自動同期再有効化
    print_debug "自動同期再有効化..."
    kubectl patch application external-secrets-operator -n argocd --type merge -p '{
        "spec": {
            "syncPolicy": {
                "automated": {
                    "prune": true,
                    "selfHeal": true
                }   
            }
        }
    }'
    
else
    print_error "Dry-run同期に問題があります。手動確認が必要です。"
    exit 1
fi

# クリーンアップ
rm -f /tmp/eso-current-state.yaml

# 最終確認
print_status "=== 移行結果確認 ==="
echo "ArgoCD Application状態:"
kubectl get application external-secrets-operator -n argocd

echo ""
echo "External Secrets Operator状態:"
kubectl get pods -n external-secrets-system

echo ""
echo "Helm状態:"
helm list -n external-secrets-system

print_status "✅ Helm → ArgoCD 管理移行完了"

cat << 'EOF'

🎯 移行完了後の管理:
- ArgoCD Application: external-secrets-operator
- 自動同期: 有効
- セルフヒール: 有効

📋 確認コマンド:
- ArgoCD状態: kubectl get applications -n argocd | grep external-secrets
- ESO状態: kubectl get pods -n external-secrets-system
- 同期状態: kubectl describe application external-secrets-operator -n argocd

EOF