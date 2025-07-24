#!/bin/bash

# Harbor イメージプルシークレット自動作成スクリプト
# 全ネームスペースに harbor-http シークレットを作成

set -euo pipefail

# カラー設定
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_status "=== Harbor イメージプルシークレット作成 ==="

# k8sクラスタ接続確認
if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
    print_error "k8sクラスタに接続できません"
    exit 1
fi

print_status "✓ k8sクラスタ接続OK"

# Harbor registry-secret の存在確認
if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret harbor-registry-secret -n arc-systems' >/dev/null 2>&1; then
    print_error "harbor-registry-secret が arc-systems ネームスペースに存在しません"
    print_warning "Phase 4のデプロイが完了していない可能性があります"
    exit 1
fi

print_status "✓ Harbor registry-secret確認完了"

# 作成対象ネームスペースのリスト
NAMESPACES=(
    "default"
    "sandbox" 
    "production"
    "staging"
    "kube-system"
)

print_status "対象ネームスペース: ${NAMESPACES[*]}"

# 各ネームスペースに harbor-http シークレットを作成
for namespace in "${NAMESPACES[@]}"; do
    print_status "処理中: $namespace ネームスペース"
    
    # ネームスペースが存在しない場合は作成
    if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl get namespace $namespace" >/dev/null 2>&1; then
        print_warning "ネームスペース $namespace が存在しません。作成中..."
        ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl create namespace $namespace"
        print_status "✓ ネームスペース $namespace を作成しました"
    fi
    
    # 既存の harbor-http シークレットを削除（存在する場合）
    if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl get secret harbor-http -n $namespace" >/dev/null 2>&1; then
        print_warning "既存の harbor-http シークレットを削除中: $namespace"
        ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl delete secret harbor-http -n $namespace"
    fi
    
    # harbor-registry-secret を harbor-http としてコピー
    print_status "harbor-http シークレットを作成中: $namespace"
    if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl get secret harbor-registry-secret -n arc-systems -o yaml | sed 's/name: harbor-registry-secret/name: harbor-http/' | sed 's/namespace: arc-systems/namespace: $namespace/' | kubectl apply -f -" >/dev/null 2>&1; then
        print_status "✓ harbor-http シークレット作成完了: $namespace"
    else
        print_error "harbor-http シークレット作成失敗: $namespace"
    fi
done

print_status "=== Harbor イメージプルシークレット作成完了 ==="

# 作成結果の確認
print_status "作成されたシークレットの確認:"
for namespace in "${NAMESPACES[@]}"; do
    if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl get secret harbor-http -n $namespace" >/dev/null 2>&1; then
        echo "  ✓ $namespace: harbor-http"
    else
        echo "  ❌ $namespace: harbor-http (作成失敗)"
    fi
done

echo ""
print_status "使用方法:"
echo "  Deployment/Pod の imagePullSecrets に以下を追加:"
echo "  imagePullSecrets:"
echo "  - name: harbor-http"
echo ""
print_status "Harbor認証情報:"
echo "  Registry: 192.168.122.100"
echo "  Username: admin"
echo "  Password: (harbor-registry-secretから自動取得)"