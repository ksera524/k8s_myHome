#!/bin/bash

# GitHub Actions Runner Controller (ARC) セットアップスクリプト
# 公式ARC対応版 - クリーンでシンプルな実装

set -euo pipefail

# 共通ライブラリを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPTS_ROOT/common-k8s-utils.sh"
source "$SCRIPTS_ROOT/common-colors.sh"

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

# GitHub認証Secret確認（ESOから取得されているはず）
print_debug "GitHub認証情報確認中..."
if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret github-token -n arc-systems' >/dev/null 2>&1; then
    print_warning "GitHub認証情報が見つかりません。ESOが同期するまで待機中..."
    sleep 30
    
    if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret github-token -n arc-systems' >/dev/null 2>&1; then
        print_error "GitHub認証情報が作成されていません。External Secrets Operatorの設定を確認してください"
        exit 1
    fi
fi
print_status "✓ GitHub認証情報確認完了"

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

print_status "✓ ServiceAccount・RBAC設定完了"

# ARC Controller状態確認（GitOpsでデプロイされているはず）
print_status "🚀 ARC Controller 状態確認中..."
if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get application arc-controller -n argocd' >/dev/null 2>&1; then
    print_status "✓ ARC Controller はGitOps経由でデプロイされています"
else
    print_warning "ARC Controller ApplicationがArgoCDに見つかりません"
fi

# 状態確認
print_status "📊 ARC状態確認中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
echo "=== ARC Controller 状態 ==="
kubectl get deployment -n arc-systems | grep controller || echo "Controller未デプロイ"

echo -e "\n=== Pods 状態 ==="
kubectl get pods -n arc-systems

echo -e "\n=== CRD 状態 ==="
kubectl get crd | grep actions.github.com || echo "ARC CRD未インストール"
EOF

print_status "✅ GitHub Actions Runner Controller セットアップ完了"
print_status ""
print_status "📋 次のステップ:"
print_status "   • make add-runner REPO=your-repo でRunnerを追加"
print_status "   • GitHubリポジトリにworkflowファイルをコミット"
print_status ""
print_status "🔐 認証: GitHub PAT (ESO管理)"
print_status "🐳 環境: Docker-in-Docker対応"
print_status "🚀 管理: GitOps + Helm"