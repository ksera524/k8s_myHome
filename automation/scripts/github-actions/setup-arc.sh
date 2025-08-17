#!/bin/bash

# GitHub Actions Runner Controller (ARC) セットアップスクリプト
# 動作確認済みHelm版で自動設定

set -euo pipefail

# 共通ライブラリを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common-k8s-utils.sh"
source "$SCRIPT_DIR/../common-colors.sh"

print_status "=== GitHub Actions Runner Controller セットアップ開始 ==="

# k8sクラスタ接続確認
print_debug "k8sクラスタ接続確認中..."
if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
    print_error "k8sクラスタに接続できません"
    exit 1
fi
print_status "✓ k8sクラスタ接続OK"

# Helm動作確認
print_debug "Helm動作確認中..."
if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'which helm' >/dev/null 2>&1; then
    print_status "Helmをインストール中..."
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash'
fi
print_status "✓ Helm準備完了"

# 名前空間作成
print_debug "arc-systems namespace確認・作成中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl create namespace arc-systems --dry-run=client -o yaml | kubectl apply -f -'

# GitHub認証Secret作成
print_debug "GitHub認証情報確認中..."
GITHUB_TOKEN=""
if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret github-token -n arc-systems' >/dev/null 2>&1; then
    GITHUB_TOKEN=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret github-token -n arc-systems -o jsonpath="{.data.github_token}" | base64 -d')
    print_status "✓ GitHub認証情報を既存secretから取得"
else
    print_error "GitHub認証情報が見つかりません。External Secrets Operatorが必要です"
    exit 1
fi

# GitHub multi-repo secret作成
print_debug "GitHub multi-repo secret作成中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl create secret generic github-multi-repo-secret --from-literal=github_token='$GITHUB_TOKEN' -n arc-systems --dry-run=client -o yaml | kubectl apply -f -"

# ServiceAccount・RBAC作成
print_debug "ServiceAccount・RBAC設定中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: github-actions-runner
  namespace: arc-systems
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: github-actions-secret-reader
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: github-actions-secret-reader
subjects:
- kind: ServiceAccount
  name: github-actions-runner
  namespace: arc-systems
roleRef:
  kind: ClusterRole
  name: github-actions-secret-reader
  apiGroup: rbac.authorization.k8s.io
EOF'

# ARC Controller インストール・アップグレード
print_status "🚀 ARC Controller インストール中..."
if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'helm status arc-controller -n arc-systems' >/dev/null 2>&1; then
    print_debug "既存のARC Controllerをアップグレード中..."
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'helm upgrade arc-controller oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller --namespace arc-systems'
else
    print_debug "新規ARC Controllerをインストール中..."
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'helm install arc-controller oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller --namespace arc-systems --create-namespace'
fi

# RunnerScaleSet インストール・アップグレード（slack.rs用）
print_status "🏃 slack.rs RunnerScaleSet セットアップ中..."
if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'helm status slack-rs-runners -n arc-systems' >/dev/null 2>&1; then
    print_debug "既存のslack-rs-runnersをアップグレード中..."
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'helm upgrade slack-rs-runners oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set --namespace arc-systems --set githubConfigUrl=https://github.com/ksera524/slack.rs --set githubConfigSecret=github-multi-repo-secret --set maxRunners=3 --set minRunners=0 --set containerMode.type=dind --set template.spec.serviceAccountName=github-actions-runner'
else
    print_debug "新規slack-rs-runnersをインストール中..."
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'helm install slack-rs-runners oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set --namespace arc-systems --set githubConfigUrl=https://github.com/ksera524/slack.rs --set githubConfigSecret=github-multi-repo-secret --set maxRunners=3 --set minRunners=0 --set containerMode.type=dind --set template.spec.serviceAccountName=github-actions-runner'
fi

# RunnerScaleSet インストール・アップグレード（k8s_myHome用）
print_status "🏃 k8s_myHome RunnerScaleSet セットアップ中..."
if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'helm status k8s-myhome-runners -n arc-systems' >/dev/null 2>&1; then
    print_debug "既存のk8s-myhome-runnersをアップグレード中..."
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'helm upgrade k8s-myhome-runners oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set --namespace arc-systems --set githubConfigUrl=https://github.com/ksera524/k8s_myHome --set githubConfigSecret=github-multi-repo-secret --set maxRunners=3 --set minRunners=1 --set containerMode.type=dind --set template.spec.serviceAccountName=github-actions-runner'
else
    print_debug "新規k8s-myhome-runnersをインストール中..."
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'helm install k8s-myhome-runners oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set --namespace arc-systems --set githubConfigUrl=https://github.com/ksera524/k8s_myHome --set githubConfigSecret=github-multi-repo-secret --set maxRunners=3 --set minRunners=1 --set containerMode.type=dind --set template.spec.serviceAccountName=github-actions-runner'
fi

# 状態確認
print_status "📊 ARC状態確認中..."
sleep 10

ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
echo "=== ARC Controller 状態 ==="
kubectl get deployment -n arc-systems

echo -e "\n=== RunnerScaleSets 状態 ==="
helm list -n arc-systems

echo -e "\n=== Pods 状態 ==="
kubectl get pods -n arc-systems

echo -e "\n=== AutoscalingRunnerSets 状態 ==="
kubectl get autoscalingrunnersets -n arc-systems 2>/dev/null || echo "AutoscalingRunnerSets CRDがまだ準備中..."
EOF

print_status "✅ GitHub Actions Runner Controller セットアップ完了"
print_status ""
print_status "📋 利用可能なRunnerScaleSet:"
print_status "   • slack-rs-runners    - slack.rsリポジトリ専用"
print_status "   • k8s-myhome-runners  - k8s_myHomeリポジトリ専用"
print_status ""
print_status "⭐ Workflow内での使用方法:"
print_status "   runs-on: slack-rs-runners    # slack.rs専用"
print_status "   runs-on: k8s-myhome-runners  # k8s_myHome専用"
print_status ""
print_status "🔐 認証: Individual GitHub PAT (ESO管理)"
print_status "🐳 環境: Docker-in-Docker対応"
print_status "🚀 管理: Helm + GitOps統合"