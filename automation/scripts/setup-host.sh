#!/bin/bash

# Phase 1: 各種アプリケーションinstall
# Ubuntu 24.04 LTS ホストマシン準備スクリプト

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root"
   exit 1
fi

print_status "Starting Phase 1: Host machine setup for k8s migration"

# 1. System update
print_status "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# 2. Install virtualization packages
print_status "Installing QEMU/KVM and libvirt packages..."
sudo apt install -y \
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
sudo apt install -y \
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
wget -O- https://apt.releases.hashicorp.com/gpg | \
    gpg --dearmor | \
    sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update
sudo apt install -y terraform

# 5. Install Ansible
print_status "Installing Ansible..."
sudo apt install -y ansible

# 6. Install Docker (for building and testing)
print_status "Installing Docker..."
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 7. Install kubectl
print_status "Installing kubectl..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubectl

# 8. Install helm
print_status "Installing Helm..."
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install -y helm

# 9. Add user to required groups
print_status "Adding user to required groups..."
sudo usermod -aG libvirt $USER
sudo usermod -aG kvm $USER
sudo usermod -aG docker $USER

# 10. Check virtualization support
print_status "Checking virtualization support..."
if kvm-ok; then
    print_status "KVM virtualization is supported"
else
    print_warning "KVM virtualization may not be fully supported. Please check BIOS settings."
fi

# 11. Enable and start services
print_status "Enabling and starting required services..."
sudo systemctl enable libvirtd
sudo systemctl start libvirtd
sudo systemctl enable docker
sudo systemctl start docker

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