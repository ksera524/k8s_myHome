#!/bin/bash

# 完全クリーンアップ＆デプロイスクリプト

set -euo pipefail

# Colors for output
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

print_status "=== 完全クリーンアップ開始 ==="

# 1. 全てのk8s関連VMを強制削除
print_status "既存VMを削除中..."
for vm in $(sudo virsh list --all --name | grep k8s); do
    sudo virsh destroy "$vm" 2>/dev/null || true
    sudo virsh undefine "$vm" --remove-all-storage 2>/dev/null || true
done

# 2. libvirt設定ファイル削除
sudo rm -f /etc/libvirt/qemu/k8s-*.xml
sudo rm -f /var/lib/libvirt/images/k8s-*
sudo rm -f /var/lib/libvirt/images/*-init-*.iso

# 3. Terraform状態完全削除
rm -rf .terraform/
rm -f terraform.tfstate*
rm -f tfplan

# 4. libvirtd再起動
sudo systemctl restart libvirtd

print_status "=== 新しい設計でデプロイ開始 ==="

# 5. 設定ファイル確認（既に新しい設計）

# 6. SSH公開鍵設定
SSH_PUB_KEY=$(cat ~/.ssh/id_rsa.pub)
cat > terraform.tfvars << EOF
vm_user = "k8suser"
ssh_public_key = "$SSH_PUB_KEY"
control_plane_ip = "192.168.122.10"
worker_ips = ["192.168.122.11", "192.168.122.12"]
network_gateway = "192.168.122.1"
EOF

# 7. Terraform初期化＆実行
terraform init
terraform plan -out=tfplan
terraform apply tfplan

if [[ $? -eq 0 ]]; then
    print_status "=== デプロイ完了 ==="
    print_status "VM接続コマンド:"
    echo "ssh k8suser@192.168.122.10  # Control Plane"
    echo "ssh k8suser@192.168.122.11  # Worker Node 1"
    echo "ssh k8suser@192.168.122.12  # Worker Node 2"
else
    print_error "デプロイに失敗しました"
    exit 1
fi