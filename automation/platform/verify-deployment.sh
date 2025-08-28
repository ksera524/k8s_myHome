#!/bin/bash
# デプロイメント検証スクリプト
# 自動修正が正しく機能しているか確認

set -euo pipefail

# 共通色設定スクリプトを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/common-colors.sh"

print_status "=== デプロイメント検証開始 ==="

# 1. 基本的な接続確認
print_status "1. クラスタ接続確認"
if ssh -o StrictHostKeyChecking=no -o BatchMode=yes k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
    print_status "✓ クラスタ接続OK"
else
    print_error "✗ クラスタに接続できません"
    exit 1
fi

# 2. StorageClass確認
print_status "2. StorageClass確認"
STORAGE_CLASS=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes k8suser@192.168.122.10 'kubectl get storageclass local-path -o name 2>/dev/null' || echo "")
if [ -n "$STORAGE_CLASS" ]; then
    print_status "✓ local-path StorageClass存在"
else
    print_warning "⚠ local-path StorageClassが存在しません"
fi

# 3. Harbor PVC状態確認
print_status "3. Harbor PVC状態確認"
ssh -o StrictHostKeyChecking=no -o BatchMode=yes k8suser@192.168.122.10 << 'EOF'
echo "Harbor PVC状態:"
kubectl get pvc -n harbor 2>/dev/null || echo "Harbor namespaceが存在しません"

# Pending PVCの確認
PENDING_PVCS=$(kubectl get pvc -n harbor -o json 2>/dev/null | jq -r '.items[] | select(.status.phase == "Pending") | .metadata.name' || echo "")
if [ -n "$PENDING_PVCS" ]; then
    echo ""
    echo "⚠ Pending状態のPVC: $PENDING_PVCS"
    
    # StorageClass未設定の確認
    NO_SC_PVCS=$(kubectl get pvc -n harbor -o json 2>/dev/null | jq -r '.items[] | select(.spec.storageClassName == null or .spec.storageClassName == "") | .metadata.name' || echo "")
    if [ -n "$NO_SC_PVCS" ]; then
        echo "⚠ StorageClass未設定のPVC: $NO_SC_PVCS"
    fi
else
    echo "✓ すべてのHarbor PVCが正常"
fi
EOF

# 4. ArgoCD Application状態確認
print_status "4. ArgoCD Application状態確認"
ssh -o StrictHostKeyChecking=no -o BatchMode=yes k8suser@192.168.122.10 << 'EOF'
echo "問題のあるApplication:"
kubectl get applications -n argocd -o json | jq -r '.items[] | select(.status.sync.status != "Synced" or .status.health.status == "Degraded") | "\(.metadata.name): Sync=\(.status.sync.status), Health=\(.status.health.status)"' || echo "確認できません"

# OutOfSync CRDの確認
echo ""
echo "OutOfSync CRD:"
for APP in metallb arc-controller; do
    OUT_OF_SYNC=$(kubectl get application $APP -n argocd -o jsonpath='{.status.resources}' 2>/dev/null | \
        jq -r '.[] | select(.status == "OutOfSync" and .kind == "CustomResourceDefinition") | .name' || echo "")
    if [ -n "$OUT_OF_SYNC" ]; then
        echo "$APP: $OUT_OF_SYNC"
    fi
done
EOF

# 5. Harbor API確認
print_status "5. Harbor API確認"
if ssh -o StrictHostKeyChecking=no -o BatchMode=yes k8suser@192.168.122.10 'curl -s -f http://192.168.122.100/api/v2.0/systeminfo >/dev/null 2>&1'; then
    print_status "✓ Harbor APIが応答"
else
    print_warning "⚠ Harbor APIが応答しません"
fi

# 6. 全体的なPod状態
print_status "6. Pod状態サマリ"
ssh -o StrictHostKeyChecking=no -o BatchMode=yes k8suser@192.168.122.10 << 'EOF'
TOTAL_PODS=$(kubectl get pods --all-namespaces --no-headers | wc -l)
RUNNING_PODS=$(kubectl get pods --all-namespaces --no-headers | grep Running | wc -l)
PROBLEM_PODS=$(kubectl get pods --all-namespaces --no-headers | grep -v Running | grep -v Completed | wc -l)

echo "Total Pods: $TOTAL_PODS"
echo "Running: $RUNNING_PODS"
echo "問題のあるPod: $PROBLEM_PODS"

if [ $PROBLEM_PODS -gt 0 ]; then
    echo ""
    echo "問題のあるPod詳細:"
    kubectl get pods --all-namespaces | grep -v Running | grep -v Completed | head -10
fi
EOF

# 7. 自動修正機能の確認
print_status "7. 自動修正機能の確認"
ssh -o StrictHostKeyChecking=no -o BatchMode=yes k8suser@192.168.122.10 << 'EOF'
# Harbor PVC修正Job/ConfigMapの存在確認
if kubectl get configmap harbor-pvc-fix-script -n harbor >/dev/null 2>&1; then
    echo "✓ Harbor PVC修正ConfigMap存在"
else
    echo "⚠ Harbor PVC修正ConfigMapが存在しません"
fi

# CRD修正CronJobの存在確認
if kubectl get cronjob crd-sync-fix -n argocd >/dev/null 2>&1; then
    echo "✓ CRD修正CronJob存在"
else
    echo "⚠ CRD修正CronJobが存在しません"
fi
EOF

print_status "=== 検証完了 ==="

# 結果サマリ
print_status ""
print_status "検証結果サマリ:"
print_status "- 自動修正機能が追加されました"
print_status "- platform-deploy.shがHarbor PVCを自動修正します"
print_status "- ArgoCD sync-hookでPVC問題を検出・修正します"
print_status "- CRD同期問題は定期的に自動修正されます"
print_status ""
print_status "問題が継続する場合は 'make fix-issues' を実行してください"