#!/bin/bash
# StorageとCRD問題の修正スクリプト

set -euo pipefail

# 共通色設定スクリプトを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/common-colors.sh"

print_status "=== Storage と CRD 問題の修正開始 ==="

# 1. local-path-provisionerの確認と待機
print_status "1. local-path-provisioner の確認"
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
# local-path-provisionerが正常に動作しているか確認
echo "local-path-provisioner の状態確認..."
kubectl wait --namespace local-path-storage --for=condition=ready pod -l app=local-path-provisioner --timeout=300s || {
    echo "警告: local-path-provisioner がまだ起動していません"
    echo "手動でデプロイします..."
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml
    kubectl wait --namespace local-path-storage --for=condition=ready pod -l app=local-path-provisioner --timeout=300s
}

# StorageClass が存在するか確認
if ! kubectl get storageclass local-path >/dev/null 2>&1; then
    echo "警告: local-path StorageClass が存在しません"
    echo "手動で作成します..."
    cat <<YAML | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
YAML
fi

echo "✓ local-path-provisioner 確認完了"
EOF

# 2. Harbor PVC問題の修正（StorageClassなしのPVC検出と修正）
print_status "2. Harbor PVC 問題の修正"
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
# StorageClassが設定されていないPVCを検出
echo "StorageClass未設定のPVCを検出中..."
PENDING_PVCS=$(kubectl get pvc -A -o json | jq -r '.items[] | select(.spec.storageClassName == null or .spec.storageClassName == "") | "\(.metadata.namespace)/\(.metadata.name)"')

if [ -n "$PENDING_PVCS" ]; then
    echo "StorageClass未設定のPVC発見:"
    echo "$PENDING_PVCS"
    
    # 各PVCに対して修正を実行
    for PVC in $PENDING_PVCS; do
        NAMESPACE=$(echo $PVC | cut -d'/' -f1)
        NAME=$(echo $PVC | cut -d'/' -f2)
        
        echo "修正中: $NAMESPACE/$NAME"
        
        # PVCの現在の設定を取得
        kubectl get pvc -n $NAMESPACE $NAME -o yaml > /tmp/pvc-$NAME.yaml
        
        # StorageClassを追加してパッチを適用
        kubectl patch pvc -n $NAMESPACE $NAME --type='json' -p='[{"op": "add", "path": "/spec/storageClassName", "value": "local-path"}]' || {
            echo "パッチ失敗、PVCを再作成します..."
            # PVCの再作成が必要な場合
            SIZE=$(kubectl get pvc -n $NAMESPACE $NAME -o jsonpath='{.spec.resources.requests.storage}')
            kubectl delete pvc -n $NAMESPACE $NAME --wait=false
            cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $NAME
  namespace: $NAMESPACE
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: $SIZE
YAML
        }
    done
else
    echo "✓ すべてのPVCにStorageClassが設定されています"
fi

echo "✓ PVC修正完了"
EOF

# 3. MetalLB CRD問題の修正
print_status "3. MetalLB CRD 問題の修正"
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
echo "古いMetalLB CRDを確認中..."

# 古いCRDの存在確認
OLD_CRDS=$(kubectl get crd | grep metallb.io | grep v1beta1 || true)
if [ -n "$OLD_CRDS" ]; then
    echo "古いCRDを削除します:"
    echo "$OLD_CRDS"
    
    # MetalLBのpodを一時停止
    kubectl scale deployment -n metallb-system controller --replicas=0 || true
    kubectl delete daemonset -n metallb-system speaker || true
    
    # 古いCRDを削除
    kubectl get crd | grep metallb.io | awk '{print $1}' | xargs -I {} kubectl delete crd {} || true
    
    # ArgoCDに再同期を指示
    kubectl patch application metallb -n argocd --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}' || true
else
    echo "✓ 古いMetalLB CRDは存在しません"
fi

echo "✓ MetalLB CRD修正完了"
EOF

# 4. ARC Controller CRD問題の修正
print_status "4. ARC Controller CRD 問題の修正"
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
echo "ARC Controller CRDを確認中..."

# CRDの存在確認と再作成
ARC_CRDS=$(kubectl get crd | grep actions.github.com || true)
if [ -z "$ARC_CRDS" ]; then
    echo "ARC Controller CRDが存在しません、手動同期を実行..."
    kubectl patch application arc-controller -n argocd --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}' || true
else
    echo "✓ ARC Controller CRDは存在します"
    
    # 既存のCRDに問題がある場合は再作成
    kubectl get crd autoscalinglisteners.actions.github.com -o yaml | grep -q "v1alpha1" || {
        echo "CRDバージョンが古い可能性があります、再作成します..."
        kubectl delete crd autoscalinglisteners.actions.github.com autoscalingrunnersets.actions.github.com || true
        kubectl patch application arc-controller -n argocd --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}' || true
    }
fi

echo "✓ ARC Controller CRD修正完了"
EOF

# 5. 全体の同期状態を確認
print_status "5. ArgoCD Application の同期状態確認"
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
echo "すべてのApplicationを再同期中..."

# OutOfSyncのApplicationを検出して再同期
OUT_OF_SYNC=$(kubectl get applications -n argocd -o json | jq -r '.items[] | select(.status.sync.status != "Synced") | .metadata.name')

if [ -n "$OUT_OF_SYNC" ]; then
    echo "OutOfSyncのApplication:"
    echo "$OUT_OF_SYNC"
    
    for APP in $OUT_OF_SYNC; do
        echo "再同期: $APP"
        kubectl patch application $APP -n argocd --type merge -p '{"operation":{"sync":{"revision":"HEAD","prune":true,"syncOptions":["ApplyOutOfSyncOnly=true"]}}}' || true
    done
    
    # 同期完了を待機
    sleep 30
fi

# 最終状態を表示
echo ""
echo "=== 最終状態 ==="
kubectl get applications -n argocd
echo ""
kubectl get pvc -A | grep -E "(Pending|Bound)" || true
echo ""
kubectl get pods -A | grep -v Running | grep -v Completed || true

echo "✓ 同期状態確認完了"
EOF

print_status "=== 修正スクリプト完了 ==="
print_status "問題が解決しない場合は、個別にトラブルシューティングが必要です"