#!/bin/bash

# GitHub Actions Runnerを保護するスクリプト
# ArgoCDからRunnerリソースを除外し、Helmで直接管理

set -euo pipefail

# 共通ライブラリを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPTS_ROOT/common-colors.sh"

print_status "=== GitHub Actions Runner保護スクリプト ==="

# 1. ArgoCDのarc-controllerアプリケーションを削除
print_status "ArgoCDのarc-controllerアプリケーションを削除中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl delete application arc-controller -n argocd --ignore-not-found=true'
print_status "✓ ArgoCDアプリケーション削除完了"

# 2. ARC Controllerが存在しない場合はHelmでインストール
print_status "ARC Controller状態確認中..."
if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'helm list -n arc-systems | grep -q arc-controller'; then
    print_status "ARC ControllerをHelmでインストール中..."
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'helm upgrade --install arc-controller oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller --namespace arc-systems --create-namespace --set crds.install=true --version 0.12.1 --wait --timeout 300s'
    print_status "✓ ARC Controllerインストール完了"
else
    print_status "✓ ARC Controllerは既に存在"
fi

# 3. RunnerリソースからArgoCDラベルを削除
print_status "RunnerリソースからArgoCDラベルを削除中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
# AutoscalingRunnerSetsからラベル削除
kubectl get autoscalingrunnersets -n arc-systems -o name | while read rs; do
    kubectl label $rs -n arc-systems argocd.argoproj.io/instance- 2>/dev/null || true
    kubectl annotate $rs -n arc-systems argocd.argoproj.io/sync-wave- 2>/dev/null || true
done

# すべてのRunnerリソースからArgoCDラベルを削除
kubectl label -n arc-systems deployment,serviceaccount,secret,configmap,service --selector="" argocd.argoproj.io/instance- 2>/dev/null || true
EOF
print_status "✓ ArgoCDラベル削除完了"

# 4. 状態確認
print_status "=== 現在の状態 ==="
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
echo "ARC Controller:"
kubectl get deployment -n arc-systems arc-controller-gha-rs-controller -o wide 2>/dev/null || echo "  Controller未起動"

echo ""
echo "AutoscalingRunnerSets:"
kubectl get autoscalingrunnersets -n arc-systems 2>/dev/null || echo "  RunnerSets未作成"

echo ""
echo "Helm Releases:"
helm list -n arc-systems 2>/dev/null || echo "  Helm releases未作成"
EOF

print_status "=== Runner保護完了 ==="
print_status "✅ GitHub Actions RunnerはArgoCDの管理外になりました"
print_status "✅ Helmで直接管理されるため、削除されません"