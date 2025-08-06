#!/bin/bash

# 手動修正が必要だった項目の自動化スクリプト
# setup-storage.sh実行後に不足していた設定を補う

set -euo pipefail

# スクリプトディレクトリ取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 共通色設定スクリプトを読み込み
source "$SCRIPT_DIR/../scripts/common-colors.sh"

print_status "Fixing missing directories and configurations..."

MOUNT_BASE="/mnt/k8s-storage"

# 1. Ensure all directories exist
print_status "Creating missing directories..."

# Create local-volumes directory if missing
if [[ ! -d "$MOUNT_BASE/local-volumes" ]]; then
    sudo mkdir -p "$MOUNT_BASE/local-volumes"
    print_status "Created local-volumes directory"
fi

# Create application directories if missing
for app in cloudflared hitomi pepup rss slack; do
    if [[ ! -d "$MOUNT_BASE/local-volumes/$app" ]]; then
        sudo mkdir -p "$MOUNT_BASE/local-volumes/$app"
        print_status "Created $app directory"
    fi
done

# 2. Fix permissions
print_status "Setting correct permissions..."
sudo chown -R $USER:$USER "$MOUNT_BASE"
sudo chmod -R 755 "$MOUNT_BASE"
sudo chmod 777 "$MOUNT_BASE/nfs-share"

# 3. Ensure NFS export is configured
print_status "Checking NFS export configuration..."
if ! sudo exportfs -v | grep -q "$MOUNT_BASE/nfs-share"; then
    print_status "Adding NFS export..."
    echo "$MOUNT_BASE/nfs-share *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
    sudo systemctl restart nfs-kernel-server
    sudo exportfs -ra
    print_status "NFS export configured"
else
    print_status "NFS export already configured"
fi

# 4. Ensure libvirtd is running
print_status "Ensuring libvirtd service is running..."
if ! systemctl is-active --quiet libvirtd; then
    sudo systemctl start libvirtd
    sudo systemctl enable libvirtd
    print_status "Started libvirtd service"
else
    print_status "libvirtd service is already running"
fi

# 5. Verify setup
print_status "Verifying fixes..."

echo "=== Directory Structure ==="
ls -la "$MOUNT_BASE/"
echo ""
echo "=== Application Directories ==="
ls -la "$MOUNT_BASE/local-volumes/"
echo ""
echo "=== NFS Exports ==="
sudo exportfs -v
echo ""
echo "=== Service Status ==="
systemctl is-active libvirtd && echo "libvirtd: Active" || echo "libvirtd: Inactive"
systemctl is-active nfs-kernel-server && echo "nfs-server: Active" || echo "nfs-server: Inactive"

print_status "All fixes applied successfully!"
print_status "You can now run ./automation/scripts/verify-setup.sh to confirm everything is working"