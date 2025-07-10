#!/bin/bash

# Phase 1: 外部ストレージ設定スクリプト
# USB外部ストレージをk8s用に設定

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root"
   exit 1
fi

print_status "Starting external storage setup for k8s cluster"

# 1. Detect USB storage devices
print_status "Detecting USB storage devices..."
echo "Available block devices:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,LABEL,UUID | grep -E "(disk|part)"

echo ""
print_status "USB devices:"
lsusb | grep -i "storage\|disk\|drive" || echo "No USB storage devices found in lsusb output"

echo ""
print_status "Disk usage information:"
df -h | head -1
df -h | grep -E "(sd[b-z]|nvme|mmc)" || echo "No additional storage devices mounted"

# 2. Interactive device selection
echo ""
print_input "Please identify your USB external storage device from the list above."
print_input "Enter the device name (e.g., sdb, sdc, nvme0n1): "
read -r DEVICE_NAME

# Validate device
if [[ ! -b "/dev/$DEVICE_NAME" ]]; then
    print_error "Device /dev/$DEVICE_NAME does not exist"
    exit 1
fi

# Safety check
echo ""
print_warning "WARNING: This will set up /dev/$DEVICE_NAME for k8s storage"
print_warning "Current partition table for /dev/$DEVICE_NAME:"
sudo fdisk -l /dev/$DEVICE_NAME 2>/dev/null || echo "Could not read partition table"

echo ""
print_input "Are you sure you want to proceed with /dev/$DEVICE_NAME? (yes/no): "
read -r CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    print_status "Operation cancelled"
    exit 0
fi

# 3. Get UUID of the device/partition
DEVICE_PATH="/dev/$DEVICE_NAME"
if [[ "$DEVICE_NAME" =~ [0-9]$ ]]; then
    # Already a partition
    PARTITION_PATH="$DEVICE_PATH"
else
    # Assume first partition
    if [[ "$DEVICE_NAME" =~ ^nvme ]]; then
        PARTITION_PATH="${DEVICE_PATH}p1"
    else
        PARTITION_PATH="${DEVICE_PATH}1"
    fi
fi

print_status "Using partition: $PARTITION_PATH"

# Check if partition exists
if [[ ! -b "$PARTITION_PATH" ]]; then
    print_warning "Partition $PARTITION_PATH does not exist"
    print_input "Do you want to create a new partition? (yes/no): "
    read -r CREATE_PARTITION
    
    if [[ "$CREATE_PARTITION" == "yes" ]]; then
        print_status "Creating new partition on $DEVICE_PATH"
        sudo parted "$DEVICE_PATH" --script -- mklabel gpt
        sudo parted "$DEVICE_PATH" --script -- mkpart primary ext4 0% 100%
        
        # Format the partition
        print_status "Formatting partition with ext4..."
        sudo mkfs.ext4 -F "$PARTITION_PATH"
        
        print_status "Setting filesystem label..."
        sudo e2label "$PARTITION_PATH" "k8s-storage"
    else
        print_error "Cannot proceed without a valid partition"
        exit 1
    fi
fi

# Get UUID
UUID=$(sudo blkid -s UUID -o value "$PARTITION_PATH")
if [[ -z "$UUID" ]]; then
    print_error "Could not get UUID for $PARTITION_PATH"
    exit 1
fi

print_status "Found UUID: $UUID"

# 4. Create mount directories
MOUNT_BASE="/mnt/k8s-storage"
print_status "Creating mount directories..."
sudo mkdir -p "$MOUNT_BASE"

# 5. Set up fstab entry
print_status "Setting up persistent mount in /etc/fstab..."

# Backup fstab
sudo cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)

# Remove any existing entry for this UUID
sudo sed -i "/UUID=$UUID/d" /etc/fstab

# Add new entry
echo "UUID=$UUID $MOUNT_BASE ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab

# 6. Mount the storage
print_status "Mounting storage..."
sudo systemctl daemon-reload
sudo mount "$MOUNT_BASE"

# Verify mount
if mountpoint -q "$MOUNT_BASE"; then
    print_status "Storage successfully mounted at $MOUNT_BASE"
else
    print_error "Failed to mount storage"
    exit 1
fi

# 7. Create subdirectories after mounting
print_status "Creating subdirectories..."
sudo mkdir -p "$MOUNT_BASE/nfs-share"
sudo mkdir -p "$MOUNT_BASE/local-volumes"

# Create application-specific directories
for app in factorio cloudflared hitomi pepup rss s3s slack; do
    sudo mkdir -p "$MOUNT_BASE/local-volumes/$app"
done

# 8. Set permissions
print_status "Setting permissions..."
sudo chown -R "$USER:$USER" "$MOUNT_BASE"
sudo chmod -R 755 "$MOUNT_BASE"

# Set specific permissions for NFS share
sudo chmod 777 "$MOUNT_BASE/nfs-share"

# 9. Install and configure NFS server
print_status "Installing NFS server..."
sudo apt update
sudo apt install -y nfs-kernel-server

# Configure NFS exports
print_status "Configuring NFS exports..."
NFS_EXPORT="$MOUNT_BASE/nfs-share *(rw,sync,no_subtree_check,no_root_squash)"

# Backup exports file
sudo cp /etc/exports /etc/exports.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true

# Add NFS export (remove existing first)
sudo sed -i "\|$MOUNT_BASE/nfs-share|d" /etc/exports
echo "$NFS_EXPORT" | sudo tee -a /etc/exports

# Restart NFS services
print_status "Starting NFS services..."
sudo systemctl enable nfs-kernel-server
sudo systemctl restart nfs-kernel-server
sudo exportfs -ra

# Ensure libvirtd is running for next steps
print_status "Ensuring libvirtd service is running..."
sudo systemctl start libvirtd
sudo systemctl enable libvirtd

# 9. Test NFS mount locally
print_status "Testing NFS mount..."
TEST_MOUNT="/tmp/nfs-test"
mkdir -p "$TEST_MOUNT"

if sudo mount -t nfs localhost:"$MOUNT_BASE/nfs-share" "$TEST_MOUNT"; then
    print_status "NFS mount test successful"
    sudo umount "$TEST_MOUNT"
    rmdir "$TEST_MOUNT"
else
    print_warning "NFS mount test failed, but continuing..."
fi

# 10. Create storage info file
print_status "Creating storage configuration file..."
cat > /tmp/k8s-storage-config.yaml << EOF
# k8s Storage Configuration
# Generated on: $(date)

storage:
  device: $DEVICE_PATH
  partition: $PARTITION_PATH
  uuid: $UUID
  mount_point: $MOUNT_BASE
  
directories:
  nfs_share: $MOUNT_BASE/nfs-share
  local_volumes: $MOUNT_BASE/local-volumes
  
nfs:
  export_path: $MOUNT_BASE/nfs-share
  server_ip: localhost
  
applications:
$(for app in factorio cloudflared hitomi pepup rss s3s slack; do
  echo "  - name: $app"
  echo "    local_path: $MOUNT_BASE/local-volumes/$app"
done)
EOF

sudo mv /tmp/k8s-storage-config.yaml "$MOUNT_BASE/k8s-storage-config.yaml"

print_status "Storage setup completed successfully!"

# 11. Display summary
echo ""
echo "=== Storage Setup Summary ==="
echo "Device: $DEVICE_PATH"
echo "Partition: $PARTITION_PATH"
echo "UUID: $UUID"
echo "Mount Point: $MOUNT_BASE"
echo "NFS Export: $MOUNT_BASE/nfs-share"
echo ""
echo "=== Available Space ==="
df -h "$MOUNT_BASE"
echo ""
echo "=== NFS Exports ==="
sudo exportfs -v
echo ""

print_status "Storage configuration saved to: $MOUNT_BASE/k8s-storage-config.yaml"
print_status "You can now proceed with VM setup using: ./automation/terraform/"