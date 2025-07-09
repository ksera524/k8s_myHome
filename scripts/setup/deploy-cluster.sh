#!/bin/bash

# Automated Kubernetes cluster deployment script
# This script orchestrates the entire cluster deployment process

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform-new"
ANSIBLE_DIR="$PROJECT_ROOT/ansible"

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    for tool in terraform ansible kubectl helm kubeseal virsh; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing tools: ${missing_tools[*]}"
        log_error "Please run scripts/setup/install-prerequisites.sh first"
        exit 1
    fi

    log_success "All prerequisites are installed"
}

# Initialize Terraform
terraform_init() {
    log_info "Initializing Terraform..."
    terraform init
    log_success "Terraform initialized"
}

# Plan Terraform deployment
terraform_plan() {
    log_info "Planning Terraform deployment..."
    terraform plan -out=tfplan

    log_info "Review the plan above. Do you want to continue? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log_warning "Deployment cancelled by user"
        exit 0
    fi

    log_success "Terraform plan approved"
}

# Apply Terraform configuration
terraform_apply() {
    log_info "Applying Terraform configuration..."
    terraform apply tfplan

    # Get outputs
    CONTROL_PLANE_IP=$(terraform output -raw control_plane_ip)
    WORKER_NODE_IPS=($(terraform output -json worker_node_ips | jq -r '.[]'))

    echo "CONTROL_PLANE_IP=$CONTROL_PLANE_IP" > "$PROJECT_ROOT/.env"
    echo "WORKER_1_IP=${WORKER_NODE_IPS[0]}" >> "$PROJECT_ROOT/.env"
    echo "WORKER_2_IP=${WORKER_NODE_IPS[1]}" >> "$PROJECT_ROOT/.env"

    log_success "Terraform applied successfully"
    log_info "Control Plane IP: $CONTROL_PLANE_IP"
    log_info "Worker Node IPs: ${WORKER_NODE_IPS[*]}"
}

# Update Ansible inventory
update_ansible_inventory() {
    log_info "Updating Ansible inventory..."

    source "$PROJECT_ROOT/.env"

    # Update inventory file
    sed -i "s/192.168.122.10/$CONTROL_PLANE_IP/g" "$ANSIBLE_DIR/inventory/hosts.yml"
    sed -i "s/192.168.122.11/$WORKER_1_IP/g" "$ANSIBLE_DIR/inventory/hosts.yml"
    sed -i "s/192.168.122.12/$WORKER_2_IP/g" "$ANSIBLE_DIR/inventory/hosts.yml"

    log_success "Ansible inventory updated"
}

# Wait for VMs to be ready
wait_for_vms() {
    log_info "Waiting for VMs to be ready..."

    source "$PROJECT_ROOT/.env"

    local max_attempts=30
    local attempt=1

    for ip in "$CONTROL_PLANE_IP" "$WORKER_1_IP" "$WORKER_2_IP"; do
        log_info "Waiting for $ip to be accessible..."

        while [[ $attempt -le $max_attempts ]]; do
            if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@"$ip" "echo 'VM is ready'" &>/dev/null; then
                log_success "$ip is ready"
                break
            fi

            log_info "Attempt $attempt/$max_attempts failed, retrying in 10 seconds..."
            sleep 10
            ((attempt++))
        done

        if [[ $attempt -gt $max_attempts ]]; then
            log_error "Failed to connect to $ip after $max_attempts attempts"
            exit 1
        fi

        attempt=1
    done

    log_success "All VMs are ready"
}

# Run Ansible playbook
run_ansible() {
    log_info "Running Ansible playbook..."

    cd "$ANSIBLE_DIR"

    # Check Ansible connectivity
    ansible -i inventory/hosts.yml all -m ping

    # Run the main playbook
    ansible-playbook -i inventory/hosts.yml playbooks/site.yml

    log_success "Ansible playbook completed"
}

# Setup kubectl access
setup_kubectl() {
    log_info "Setting up kubectl access..."

    source "$PROJECT_ROOT/.env"

    # Copy kubeconfig from control plane
    scp -o StrictHostKeyChecking=no ubuntu@"$CONTROL_PLANE_IP":/home/ubuntu/.kube/config ~/.kube/config

    # Update server address in kubeconfig
    kubectl config set-cluster kubernetes --server="https://$CONTROL_PLANE_IP:6443"

    # Test kubectl access
    kubectl get nodes

    log_success "kubectl access configured"
}

# Deploy basic infrastructure
deploy_infrastructure() {
    log_info "Deploying basic infrastructure..."

    # Deploy namespaces
    kubectl apply -f "$PROJECT_ROOT/k8s-manifests/infrastructure/namespaces.yaml"

    # Install Sealed Secrets Controller
    kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.18.0/controller.yaml

    # Wait for Sealed Secrets Controller
    kubectl wait --for=condition=ready pod -l name=sealed-secrets-controller -n kube-system --timeout=300s

    # Deploy storage configuration
    source "$PROJECT_ROOT/.env"
    sed "s/REPLACE_WITH_NFS_SERVER_IP/$CONTROL_PLANE_IP/g" "$PROJECT_ROOT/k8s-manifests/infrastructure/nfs-storage.yaml" | kubectl apply -f -

    log_success "Basic infrastructure deployed"
}

# Verify cluster
verify_cluster() {
    log_info "Verifying cluster..."

    echo "=== Cluster Nodes ==="
    kubectl get nodes -o wide

    echo "=== System Pods ==="
    kubectl get pods -n kube-system

    echo "=== Storage Classes ==="
    kubectl get storageclass

    echo "=== Persistent Volumes ==="
    kubectl get pv

    log_success "Cluster verification completed"
}

# Generate deployment summary
generate_summary() {
    log_info "Generating deployment summary..."

    source "$PROJECT_ROOT/.env"

    cat > "$PROJECT_ROOT/deployment-summary.md" << EOF
# Kubernetes Cluster Deployment Summary

## Cluster Information
- **Deployment Date**: $(date)
- **Control Plane IP**: $CONTROL_PLANE_IP
- **Worker Node 1 IP**: $WORKER_1_IP
- **Worker Node 2 IP**: $WORKER_2_IP

## Access Information
- **kubectl**: Configured and ready to use
- **SSH Access**: Available to all nodes using ~/.ssh/id_rsa

## Next Steps
1. Deploy Secrets: Run \`./scripts/secrets/create-secrets.sh\`
2. Deploy Applications: Use GitHub Actions or manual kubectl apply
3. Configure monitoring and logging
4. Setup backup procedures

## Useful Commands
\`\`\`bash
# Check cluster status
kubectl get nodes -o wide

# Access control plane
ssh ubuntu@$CONTROL_PLANE_IP

# View all resources
kubectl get all --all-namespaces
\`\`\`
EOF

    log_success "Deployment summary saved to deployment-summary.md"
}

# Main deployment function
main() {
    log_info "Starting Kubernetes cluster deployment..."

    check_prerequisites

    pushd "$TERRAFORM_DIR" > /dev/null
    terraform_init
    terraform_plan
    terraform_apply
    popd > /dev/null

    update_ansible_inventory
    wait_for_vms
    run_ansible
    setup_kubectl
    deploy_infrastructure
    verify_cluster
    generate_summary

    log_success "Kubernetes cluster deployment completed successfully!"
    log_info "Review deployment-summary.md for next steps"
}

# Handle script interruption
trap 'log_error "Deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@"
