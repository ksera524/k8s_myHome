#!/bin/bash

# Phase 3: k8s クラスタ自動構築スクリプト
# kubeadm + Flannel によるControl Plane + Worker Node 2台構成

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

print_status "=== Phase 3: k8s クラスタ自動構築開始 ==="

# 0. 前提条件確認
print_status "前提条件を確認中..."

# VM状態確認
print_debug "VM起動状態確認..."
VM_COUNT=$(sudo virsh list --state-running | grep k8s | wc -l)
if [[ $VM_COUNT -ne 3 ]]; then
    print_error "VM が3台起動していません（現在: $VM_COUNT台）"
    print_error "Phase 2のVM構築を先に完了してください"
    exit 1
fi

print_status "✓ VM 3台が起動中"

# SSH接続確認
print_debug "SSH接続確認..."
for ip in 192.168.122.10 192.168.122.11 192.168.122.12; do
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no k8suser@$ip 'echo "SSH OK"' >/dev/null 2>&1; then
        print_error "SSH接続失敗: $ip"
        print_error "Phase 2のVM構築を確認してください"
        exit 1
    fi
done

print_status "✓ 全VM SSH接続OK"

# Ansible インストール確認
if ! command -v ansible >/dev/null 2>&1; then
    print_status "Ansibleをインストール中..."
    sudo apt update >/dev/null 2>&1
    sudo apt install -y ansible
fi

print_status "✓ Ansible利用可能"

# 1. cloud-init完了確認
print_status "cloud-init完了を確認中..."
for ip in 192.168.122.10 192.168.122.11 192.168.122.12; do
    print_debug "確認中: $ip"
    if ! ssh -o StrictHostKeyChecking=no k8suser@$ip 'sudo cloud-init status --wait' >/dev/null 2>&1; then
        print_warning "cloud-init未完了またはエラー: $ip"
        print_warning "続行しますが、エラーが発生する可能性があります"
    fi
done

print_status "✓ cloud-init確認完了"

# 2. Ansible接続テスト
print_status "Ansible接続テストを実行中..."
if ansible -i inventory.ini all -m ping >/dev/null 2>&1; then
    print_status "✓ Ansible接続テスト成功"
else
    print_error "Ansible接続テスト失敗"
    print_error "インベントリ設定を確認してください: inventory.ini"
    exit 1
fi

# 3. 既存のk8sクラスタリセット（必要に応じて）
print_status "既存k8sクラスタをリセット中..."
ansible -i inventory.ini all -b -m shell -a "kubeadm reset -f || true" >/dev/null 2>&1 || true
ansible -i inventory.ini all -b -m shell -a "rm -rf /home/k8suser/.kube || true" >/dev/null 2>&1 || true

print_debug "k8sクラスタリセット完了"

# 4. k8sクラスタ構築実行
print_status "k8sクラスタ構築を開始中..."
print_debug "この処理には数分かかります..."

if ansible-playbook -i inventory.ini k8s-setup.yml; then
    print_status "✓ k8sクラスタ構築成功"
else
    print_error "k8sクラスタ構築失敗"
    print_error "エラーログを確認してください"
    exit 1
fi

# 5. 構築結果確認
print_status "構築結果を確認中..."

# クラスタ状態確認
print_debug "Node状態確認..."
NODE_STATUS=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get nodes --no-headers' | wc -l)
if [[ $NODE_STATUS -eq 3 ]]; then
    print_status "✓ 全Node (3台) がクラスタに参加済み"
else
    print_warning "⚠ Node参加状況: $NODE_STATUS/3台"
fi

# Pod状態確認
print_debug "システムPod状態確認..."
READY_PODS=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get pods --all-namespaces --no-headers' | grep -c Running || echo "0")
print_status "✓ 実行中Pod数: $READY_PODS"

# 6. 接続情報表示
print_status "=== k8s クラスタ構築完了 ==="
echo ""
echo "=== クラスタ接続情報 ==="
echo "Control Plane: ssh k8suser@192.168.122.10"
echo "Worker Node 1: ssh k8suser@192.168.122.11"
echo "Worker Node 2: ssh k8suser@192.168.122.12"
echo ""

# クラスタ状態表示
print_status "=== クラスタ状態 ==="
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get nodes -o wide' || true
echo ""
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get pods --all-namespaces' || true

echo ""
echo "=== 外部接続用設定 ==="
echo "# kubectl設定を外部に取得"
echo "scp k8suser@192.168.122.10:/home/k8suser/.kube/config ~/.kube/config-k8s-cluster"
echo ""
echo "# 外部からクラスタ操作"
echo "export KUBECONFIG=~/.kube/config-k8s-cluster"
echo "kubectl get nodes"

echo ""
echo "=== 次のステップ ==="
echo "1. クラスタ確認: ssh k8suser@192.168.122.10 'kubectl get nodes'"
echo "2. Pod確認: ssh k8suser@192.168.122.10 'kubectl get pods --all-namespaces'"
echo "3. Phase 4: 基本インフラ構築（MetalLB, Ingress Controller等）"

# 7. 構築情報保存
if [[ -f k8s-cluster-info.txt ]]; then
    print_status "クラスタ情報が保存されました: k8s-cluster-info.txt"
    cat k8s-cluster-info.txt
fi

print_status "Phase 3 k8sクラスタ構築が完了しました！"