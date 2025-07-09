#!/bin/bash

# Prerequisites installation script for Kubernetes cluster migration
# This script installs all necessary tools on the host machine

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root"
        exit 1
    fi
}

# Check Ubuntu version
check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release; then
        log_error "This script is designed for Ubuntu. Other distributions are not supported."
        exit 1
    fi
    
    local version=$(lsb_release -rs)
    log_info "Detected Ubuntu $version"
}

# Update system packages
update_system() {
    log_info "Updating system packages..."
    sudo apt update
    sudo apt upgrade -y
    log_success "System updated"
}

# Install QEMU/KVM and libvirt
install_virtualization() {
    log_info "Installing QEMU/KVM and libvirt..."
    
    sudo apt install -y \
        qemu-kvm \
        libvirt-daemon-system \
        libvirt-clients \
        bridge-utils \
        virt-manager \
        libvirt-dev
    
    # Add user to libvirt group
    sudo usermod -a -G libvirt $USER
    
    # Start and enable libvirt
    sudo systemctl enable libvirtd
    sudo systemctl start libvirtd
    
    log_success "Virtualization tools installed"
}

# Install Terraform
install_terraform() {
    log_info "Installing Terraform..."
    
    # Install prerequisites
    sudo apt install -y gnupg software-properties-common
    
    # Add HashiCorp GPG key
    wget -O- https://apt.releases.hashicorp.com/gpg | \
        gpg --dearmor | \
        sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
    
    # Add HashiCorp repository
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
        https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
        sudo tee /etc/apt/sources.list.d/hashicorp.list
    
    # Install Terraform
    sudo apt update
    sudo apt install -y terraform
    
    # Verify installation
    terraform version
    log_success "Terraform installed"
}

# Install Ansible
install_ansible() {
    log_info "Installing Ansible..."
    
    sudo apt install -y software-properties-common
    sudo add-apt-repository --yes --update ppa:ansible/ansible
    sudo apt install -y ansible
    
    # Verify installation
    ansible --version
    log_success "Ansible installed"
}

# Install kubectl
install_kubectl() {
    log_info "Installing kubectl..."
    
    # Download kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    
    # Verify kubectl
    curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
    
    # Install kubectl
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    
    # Clean up
    rm kubectl kubectl.sha256
    
    # Verify installation
    kubectl version --client
    log_success "kubectl installed"
}

# Install Helm
install_helm() {
    log_info "Installing Helm..."
    
    curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
    sudo apt-get update
    sudo apt-get install -y helm
    
    # Verify installation
    helm version
    log_success "Helm installed"
}

# Install kubeseal
install_kubeseal() {
    log_info "Installing kubeseal..."
    
    # Get latest release
    KUBESEAL_VERSION=$(curl -s https://api.github.com/repos/bitnami-labs/sealed-secrets/releases/latest | grep tag_name | cut -d '"' -f 4)
    
    # Download and install
    wget "https://github.com/bitnami-labs/sealed-secrets/releases/download/${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION:1}-linux-amd64.tar.gz"
    tar -xvzf "kubeseal-${KUBESEAL_VERSION:1}-linux-amd64.tar.gz"
    sudo install -m 755 kubeseal /usr/local/bin/kubeseal
    
    # Clean up
    rm kubeseal "kubeseal-${KUBESEAL_VERSION:1}-linux-amd64.tar.gz"
    
    # Verify installation
    kubeseal --version
    log_success "kubeseal installed"
}

# Install additional tools
install_additional_tools() {
    log_info "Installing additional tools..."
    
    sudo apt install -y \
        git \
        curl \
        wget \
        jq \
        yq \
        tree \
        htop \
        net-tools \
        ssh \
        sshpass
    
    log_success "Additional tools installed"
}

# Setup SSH key if not exists
setup_ssh_key() {
    log_info "Checking SSH key..."
    
    if [[ ! -f ~/.ssh/id_rsa ]]; then
        log_info "Generating SSH key..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
        log_success "SSH key generated"
    else
        log_info "SSH key already exists"
    fi
}

# Create necessary directories
create_directories() {
    log_info "Creating necessary directories..."
    
    mkdir -p ~/.kube
    mkdir -p ~/k8s-cluster-backup
    
    log_success "Directories created"
}

# Main function
main() {
    log_info "Starting prerequisites installation for Kubernetes cluster migration..."
    
    check_root
    check_ubuntu
    update_system
    install_virtualization
    install_terraform
    install_ansible
    install_kubectl
    install_helm
    install_kubeseal
    install_additional_tools
    setup_ssh_key
    create_directories
    
    log_success "All prerequisites installed successfully!"
    log_warning "Please log out and log back in to apply group changes (libvirt group)"
    log_info "You can verify the installation by running: virsh list --all"
}

# Run main function
main "$@"