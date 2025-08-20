#!/bin/bash

# Phase 1: 各種アプリケーションinstall
# Ubuntu 24.04 LTS ホストマシン準備スクリプト

set -euo pipefail

# 共通カラー定義を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/common-colors.sh"

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root"
   exit 1
fi

print_status "Starting Phase 1: Host machine setup for k8s migration"

# 1. System update
print_status "Updating system packages..."
sudo -n apt update && sudo -n apt upgrade -y

# 2. Install virtualization packages
print_status "Installing QEMU/KVM and libvirt packages..."
sudo -n apt install -y \
    qemu-kvm \
    libvirt-daemon-system \
    libvirt-clients \
    bridge-utils \
    virtinst \
    virt-manager \
    virt-viewer \
    cpu-checker

# 3. Install development and automation tools
print_status "Installing development and automation tools..."
sudo -n apt install -y \
    git \
    curl \
    wget \
    unzip \
    jq \
    tree \
    htop \
    vim \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release

# 4. Install Terraform
print_status "Installing Terraform..."
# 既存のキーファイルを削除してから作成（上書き確認を回避）
sudo -n rm -f /usr/share/keyrings/hashicorp-archive-keyring.gpg
wget -O- https://apt.releases.hashicorp.com/gpg | \
    gpg --dearmor | \
    sudo -n tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo -n tee /etc/apt/sources.list.d/hashicorp.list
sudo -n apt update
sudo -n apt install -y terraform

# 5. Install Ansible
print_status "Installing Ansible..."
sudo apt install -y ansible

# 6. Install Docker (for building and testing)
print_status "Installing Docker..."
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo -n apt-get remove $pkg; done
sudo -n apt-get update
sudo -n apt-get install -y ca-certificates curl
sudo -n install -m 0755 -d /etc/apt/keyrings
sudo -n curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo -n chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo -n tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo -n apt-get update
sudo -n apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 7. Install kubectl
print_status "Installing kubectl..."
# 既存のキーファイルを削除してから作成（上書き確認を回避）
sudo -n rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo -n gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo -n tee /etc/apt/sources.list.d/kubernetes.list
sudo -n apt-get update
sudo -n apt-get install -y kubectl

# 8. Install helm
print_status "Installing Helm..."
# 既存のキーファイルを削除してから作成（上書き確認を回避）
sudo -n rm -f /usr/share/keyrings/helm.gpg
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo -n tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo -n tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo -n apt-get update
sudo -n apt-get install -y helm

# 9. Add user to required groups
print_status "Adding user to required groups..."
sudo -n usermod -aG libvirt $USER
sudo -n usermod -aG kvm $USER
sudo -n usermod -aG docker $USER

# 10. Check virtualization support
print_status "Checking virtualization support..."
if kvm-ok; then
    print_status "KVM virtualization is supported"
else
    print_warning "KVM virtualization may not be fully supported. Please check BIOS settings."
fi

# 11. Enable and start services
print_status "Enabling and starting required services..."
sudo -n systemctl enable libvirtd
sudo -n systemctl start libvirtd
sudo -n systemctl enable docker
sudo -n systemctl start docker

# 12. Verify installations
print_status "Verifying installations..."

# Check versions
echo "=== Installation Verification ==="
echo "Terraform version: $(terraform version -json | jq -r '.terraform_version')"
echo "Ansible version: $(ansible --version | head -1)"
echo "Docker version: $(docker --version)"
echo "kubectl version: $(kubectl version --client --short 2>/dev/null || echo 'kubectl installed')"
echo "Helm version: $(helm version --short)"

# Check services
echo ""
echo "=== Service Status ==="
systemctl is-active --quiet libvirtd && echo "libvirtd: Active" || echo "libvirtd: Inactive"
systemctl is-active --quiet docker && echo "docker: Active" || echo "docker: Inactive"

# Check group membership
echo ""
echo "=== Group Membership ==="
echo "Groups for user $USER: $(groups $USER)"

print_status "Phase 1 setup completed successfully!"
print_warning "Please log out and log back in (or run 'newgrp libvirt && newgrp docker') to refresh group membership."
print_status "After re-login, run: ./setup-storage.sh to continue with storage setup"

# Create next step reminder
cat > /tmp/next-steps.txt << EOF
Phase 1 completed successfully!

Next steps:
1. Log out and log back in to refresh group membership
2. Run: ./automation/scripts/setup-storage.sh
3. Run: ./automation/scripts/verify-setup.sh

EOF

print_status "Next steps saved to /tmp/next-steps.txt"

# Helm セットアップを実行
print_status "Helmセットアップを実行中..."
if [[ -f "$(dirname "$0")/setup-helm.sh" ]]; then
    "$(dirname "$0")/setup-helm.sh"
else
    print_warning "setup-helm.sh が見つかりません。Helmの手動セットアップが必要です。"
fi