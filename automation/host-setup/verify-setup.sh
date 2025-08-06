#!/bin/bash

# Phase 1: セットアップ検証スクリプト
# ホストマシンとストレージの設定を検証

set -euo pipefail

# スクリプトディレクトリ取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 共通色設定スクリプトを読み込み
source "$SCRIPT_DIR/../scripts/common-colors.sh"

# Track overall status
OVERALL_STATUS=0

# Function to check and report status
check_status() {
    local description="$1"
    local command="$2"
    
    echo -n "Checking $description... "
    if eval "$command" >/dev/null 2>&1; then
        echo "✓"
        return 0
    else
        echo "✗"
        OVERALL_STATUS=1
        return 1
    fi
}

print_status "=== Phase 1 Setup Verification ==="
echo ""

# 1. Check system packages
print_status "1. Checking installed packages..."
check_status "QEMU/KVM" "which qemu-system-x86_64"
check_status "libvirt" "which virsh"
check_status "Terraform" "which terraform"
check_status "Ansible" "which ansible"
check_status "Docker" "which docker"
check_status "kubectl" "which kubectl"
check_status "Helm" "which helm"

echo ""

# 2. Check virtualization support
print_status "2. Checking virtualization support..."
if check_status "KVM support" "kvm-ok"; then
    print_success "Hardware virtualization is supported"
else
    print_warning "Hardware virtualization may not be available"
fi

echo ""

# 3. Check services
print_status "3. Checking services..."
check_status "libvirtd service" "systemctl is-active --quiet libvirtd"
check_status "Docker service" "systemctl is-active --quiet docker"
check_status "NFS server" "systemctl is-active --quiet nfs-kernel-server"

echo ""

# 4. Check user permissions
print_status "4. Checking user permissions..."
check_status "libvirt group membership" "groups | grep -q libvirt"
check_status "kvm group membership" "groups | grep -q kvm"
check_status "docker group membership" "groups | grep -q docker"

echo ""

# 5. Check storage setup
print_status "5. Checking storage setup..."
MOUNT_BASE="/mnt/k8s-storage"

if check_status "Storage mount point" "mountpoint -q $MOUNT_BASE"; then
    print_success "Storage is properly mounted at $MOUNT_BASE"
    
    # Check available space
    AVAILABLE_SPACE=$(df -BG "$MOUNT_BASE" | tail -1 | awk '{print $4}' | sed 's/G//')
    if [[ $AVAILABLE_SPACE -gt 10 ]]; then
        print_success "Available space: ${AVAILABLE_SPACE}GB (sufficient)"
    else
        print_warning "Available space: ${AVAILABLE_SPACE}GB (may be insufficient)"
    fi
    
    # Check directory structure
    check_status "NFS share directory" "test -d $MOUNT_BASE/nfs-share"
    check_status "Local volumes directory" "test -d $MOUNT_BASE/local-volumes"
    
    # Check application directories
    for app in cloudflared hitomi pepup rss slack; do
        check_status "$app directory" "test -d $MOUNT_BASE/local-volumes/$app"
    done
else
    print_error "Storage is not properly mounted"
fi

echo ""

# 6. Check NFS setup
print_status "6. Checking NFS setup..."
if check_status "NFS exports" "sudo exportfs -v | grep -q $MOUNT_BASE/nfs-share"; then
    print_success "NFS export is configured"
    
    # Test NFS mount
    TEST_MOUNT="/tmp/nfs-verify-$$"
    mkdir -p "$TEST_MOUNT"
    
    if sudo mount -t nfs localhost:"$MOUNT_BASE/nfs-share" "$TEST_MOUNT" 2>/dev/null; then
        print_success "NFS mount test successful"
        
        # Test write access
        if sudo touch "$TEST_MOUNT/test-file" 2>/dev/null; then
            print_success "NFS write access working"
            sudo rm -f "$TEST_MOUNT/test-file"
        else
            print_warning "NFS write access may be restricted"
        fi
        
        sudo umount "$TEST_MOUNT"
    else
        print_error "NFS mount test failed"
        OVERALL_STATUS=1
    fi
    
    rmdir "$TEST_MOUNT"
else
    print_error "NFS export is not configured"
fi

echo ""

# 7. Check tool versions
print_status "7. Tool versions..."
echo "Terraform: $(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1)"
echo "Ansible: $(ansible --version | head -1)"
echo "Docker: $(docker --version)"
echo "kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
echo "Helm: $(helm version --short)"

echo ""

# 8. Check network connectivity
print_status "8. Checking network connectivity..."
check_status "Internet connectivity" "ping -c 1 8.8.8.8"
check_status "DNS resolution" "nslookup google.com"

echo ""

# 9. Check libvirt network
print_status "9. Checking libvirt network..."
if check_status "Default libvirt network" "virsh net-list --all | grep -q default"; then
    if virsh net-list | grep -q "default.*active"; then
        print_success "Default libvirt network is active"
    else
        print_warning "Default libvirt network exists but is not active"
        print_status "Starting default network..."
        sudo virsh net-start default
        sudo virsh net-autostart default
    fi
else
    print_warning "Default libvirt network not found"
fi

echo ""

# 10. Generate readiness report
print_status "10. Generating readiness report..."

REPORT_FILE="/tmp/k8s-setup-readiness-$(date +%Y%m%d_%H%M%S).txt"

cat > "$REPORT_FILE" << EOF
k8s Migration Setup Readiness Report
Generated: $(date)
Host: $(hostname)
User: $(whoami)

=== System Information ===
OS: $(lsb_release -d | cut -f2)
Kernel: $(uname -r)
Architecture: $(uname -m)
Memory: $(free -h | grep '^Mem:' | awk '{print $2}')
CPU: $(nproc) cores

=== Package Status ===
QEMU/KVM: $(which qemu-system-x86_64 >/dev/null 2>&1 && echo "✓ Installed" || echo "✗ Missing")
libvirt: $(which virsh >/dev/null 2>&1 && echo "✓ Installed" || echo "✗ Missing")
Terraform: $(which terraform >/dev/null 2>&1 && echo "✓ Installed" || echo "✗ Missing")
Ansible: $(which ansible >/dev/null 2>&1 && echo "✓ Installed" || echo "✗ Missing")
Docker: $(which docker >/dev/null 2>&1 && echo "✓ Installed" || echo "✗ Missing")
kubectl: $(which kubectl >/dev/null 2>&1 && echo "✓ Installed" || echo "✗ Missing")
Helm: $(which helm >/dev/null 2>&1 && echo "✓ Installed" || echo "✗ Missing")

=== Services Status ===
libvirtd: $(systemctl is-active --quiet libvirtd && echo "✓ Active" || echo "✗ Inactive")
Docker: $(systemctl is-active --quiet docker && echo "✓ Active" || echo "✗ Inactive")
NFS: $(systemctl is-active --quiet nfs-kernel-server && echo "✓ Active" || echo "✗ Inactive")

=== Storage Status ===
Mount Point: $MOUNT_BASE
Mounted: $(mountpoint -q $MOUNT_BASE && echo "✓ Yes" || echo "✗ No")
Available Space: $(df -BG $MOUNT_BASE 2>/dev/null | tail -1 | awk '{print $4}' || echo "Unknown")
NFS Export: $(sudo exportfs -v 2>/dev/null | grep -q $MOUNT_BASE/nfs-share && echo "✓ Configured" || echo "✗ Not configured")

=== User Permissions ===
libvirt group: $(groups | grep -q libvirt && echo "✓ Member" || echo "✗ Not member")
kvm group: $(groups | grep -q kvm && echo "✓ Member" || echo "✗ Not member")
docker group: $(groups | grep -q docker && echo "✓ Member" || echo "✗ Not member")

=== Virtualization Support ===
KVM: $(kvm-ok >/dev/null 2>&1 && echo "✓ Supported" || echo "✗ Not supported")

=== Overall Status ===
$(if [[ $OVERALL_STATUS -eq 0 ]]; then echo "✓ READY - All checks passed"; else echo "✗ NOT READY - Some checks failed"; fi)
EOF

print_status "Readiness report saved to: $REPORT_FILE"

echo ""
echo "=== Summary ==="
if [[ $OVERALL_STATUS -eq 0 ]]; then
    print_success "✓ All verification checks passed!"
    print_success "Your system is ready for Phase 2 (VM construction)"
    print_status "Next step: cd automation/terraform && terraform init"
else
    print_error "✗ Some verification checks failed"
    print_error "Please resolve the issues before proceeding to Phase 2"
    print_status "Review the readiness report: $REPORT_FILE"
fi

echo ""
print_status "Phase 1 verification completed"

exit $OVERALL_STATUS