#!/bin/bash
# Harbor PVC名前固定化のテストスクリプト

set -euo pipefail

# 共通色設定スクリプトを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/common-colors.sh"

print_status "=== Harbor PVC名前固定化テスト ==="

# 1. 現在の状態を確認
print_status "1. 現在のHarbor PVC状態確認"
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
echo "現在のPVC:"
kubectl get pvc -n harbor -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,STORAGECLASS:.spec.storageClassName,VOLUME:.spec.volumeName
EOF

# 2. Harbor ApplicationをGitOpsで更新
print_status "2. Harbor設定の更新をGitにpush"
cd "$SCRIPT_DIR/../.."
git add manifests/infrastructure/gitops/harbor/
git commit -m "fix: Harbor PVC名前を固定化してStorageClass問題を解決

- harbor-jobserviceとharbor-registryのPVCを事前作成
- existingClaimでPVC名を固定指定
- sync-waveでPVCを先に作成するよう制御

🤖 Generated with Claude Code

Co-Authored-By: Claude <noreply@anthropic.com>" || true

print_status "3. ArgoCD同期をトリガー"
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
# Harbor Applicationを手動同期
echo "Harbor Applicationを同期中..."
kubectl patch application harbor -n argocd --type merge -p '{"operation":{"sync":{"revision":"HEAD","prune":true}}}'

# 同期状態を確認
sleep 10
echo ""
echo "同期状態:"
kubectl get application harbor -n argocd -o jsonpath='{.status.sync.status}'
echo ""
EOF

# 4. PVC状態を確認
print_status "4. 更新後のPVC状態確認（30秒後）"
sleep 30
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
echo "更新後のPVC:"
kubectl get pvc -n harbor -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,STORAGECLASS:.spec.storageClassName

echo ""
echo "Harbor Pod状態:"
kubectl get pods -n harbor | grep -E "(NAME|jobservice|registry)"
EOF

print_status "=== テスト完了 ==="
print_status "注意: 実際の環境では、git pushしてArgoCD経由で同期してください"