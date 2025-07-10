#!/bin/bash

# Phase 2: Terraform VM構築セットアップスクリプト

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_input() {
    echo -e "${BLUE}[INPUT]${NC} $1"
}

print_status "Phase 2: VM構築セットアップを開始します"

# 1. SSH鍵の確認/生成
print_status "SSH鍵の確認..."
if [[ ! -f ~/.ssh/id_rsa ]]; then
    print_status "SSH鍵ペアを生成しています..."
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
    print_status "SSH鍵ペアを生成しました"
else
    print_status "SSH鍵ペアが存在します"
fi

# 2. terraform.tfvarsファイルの作成
print_status "terraform.tfvars設定ファイルを作成しています..."

if [[ -f terraform.tfvars ]]; then
    print_warning "terraform.tfvarsが既に存在します。バックアップを作成します..."
    cp terraform.tfvars terraform.tfvars.backup.$(date +%Y%m%d_%H%M%S)
fi

# SSH公開鍵を取得
SSH_PUB_KEY=$(cat ~/.ssh/id_rsa.pub)

# terraform.tfvarsファイル作成
cat > terraform.tfvars << EOF
# Phase 2 VM構築用設定
# Generated on: $(date)

# VM接続用ユーザー名
vm_user = "k8suser"

# SSH公開鍵
ssh_public_key = "$SSH_PUB_KEY"

# VM IPアドレス設定
control_plane_ip = "192.168.122.10"
worker1_ip       = "192.168.122.11"  
worker2_ip       = "192.168.122.12"

# ネットワーク設定
network_gateway = "192.168.122.1"
dns_servers     = ["8.8.8.8", "8.8.4.4"]

# NFSサーバーIP
nfs_server_ip = "192.168.122.1"
EOF

print_status "terraform.tfvarsファイルを作成しました"

# 3. ネットワーク設定確認
print_status "libvirtネットワーク設定を確認しています..."

# デフォルトネットワークが存在し、アクティブかチェック
if virsh net-list | grep -q "default.*active"; then
    print_status "libvirtデフォルトネットワークがアクティブです"
else
    print_warning "libvirtデフォルトネットワークが非アクティブです。開始します..."
    virsh net-start default
    virsh net-autostart default
fi

# ネットワーク情報表示
print_status "ネットワーク情報:"
virsh net-dumpxml default | grep -A 3 "<ip "

# 4. 使用中IPアドレスの確認
print_status "使用中IPアドレスを確認しています..."
echo "現在のネットワーク上のデバイス:"
nmap -sn 192.168.122.0/24 2>/dev/null | grep -E "(Nmap scan report|MAC Address)" || echo "スキャン結果なし"

# 5. Terraformの初期化と検証
print_status "Terraformを初期化しています..."
terraform init

print_status "Terraform設定を検証しています..."
terraform validate

print_status "Terraformプランを生成しています..."
terraform plan -out=tfplan

# 6. 構築前の最終確認
echo ""
echo "=== 構築予定のVM ==="
echo "Control Plane: 192.168.122.10 (4CPU, 8GB RAM, 50GB Disk)"
echo "Worker Node 1: 192.168.122.11 (2CPU, 4GB RAM, 30GB Disk)"
echo "Worker Node 2: 192.168.122.12 (2CPU, 4GB RAM, 30GB Disk)"
echo ""
echo "=== SSH接続コマンド ==="
echo "ssh k8suser@192.168.122.10  # Control Plane"
echo "ssh k8suser@192.168.122.11  # Worker Node 1"
echo "ssh k8suser@192.168.122.12  # Worker Node 2"
echo ""

print_input "VM構築を実行しますか？ (yes/no): "
read -r CONFIRM

if [[ "$CONFIRM" == "yes" ]]; then
    print_status "VM構築を開始します..."
    terraform apply tfplan
    
    if [[ $? -eq 0 ]]; then
        print_status "VM構築が完了しました！"
        
        # 7. 構築後の確認
        print_status "VM状態を確認しています..."
        virsh list --all
        
        print_status "VM起動完了を待機しています..."
        for ip in 192.168.122.10 192.168.122.11 192.168.122.12; do
            echo -n "Waiting for $ip... "
            while ! ping -c 1 "$ip" >/dev/null 2>&1; do
                echo -n "."
                sleep 5
            done
            echo " Ready!"
        done
        
        print_status "cloud-init完了を待機しています..."
        for ip in 192.168.122.10 192.168.122.11 192.168.122.12; do
            echo "Waiting for cloud-init on $ip..."
            ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 k8suser@$ip "sudo cloud-init status --wait" || true
        done
        
        echo ""
        print_status "=== Phase 2 完了 ==="
        print_status "次のステップ: Phase 3 (k8s構築)"
        print_status "cd ../ansible && ansible-playbook -i inventory/hosts.yml playbook.yml"
        
    else
        print_error "VM構築中にエラーが発生しました"
        exit 1
    fi
else
    print_status "VM構築をキャンセルしました"
    print_status "後で構築する場合は: terraform apply tfplan"
fi