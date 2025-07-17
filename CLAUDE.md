# CLAUDE.md
必ず日本語で応答し、コメントも日本語で書いて

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**k8s_myHome** is a production-grade home Kubernetes infrastructure project that migrates from k3s to a full 3-node cluster on virtualized infrastructure. The codebase is primarily documented in Japanese and uses a phase-based deployment approach with complete automation.

## Architecture

### Deployment Phases (Execute in Order)
1. **Phase 1** (`automation/scripts/`): Host preparation - Ubuntu 24.04 LTS setup
2. **Phase 2** (`automation/terraform/`): VM infrastructure - QEMU/KVM with libvirt
3. **Phase 3** (`automation/ansible/`): Kubernetes cluster - kubeadm-based 3-node cluster  
4. **Phase 4** (`automation/phase4/`): Core infrastructure - MetalLB, NGINX, cert-manager, ArgoCD, Harbor
5. **Phase 5** (`infra/`, `app/`): Application migration via GitOps

### Key Infrastructure Components
- **Cluster**: 1 Control Plane (192.168.122.10) + 2 Workers (192.168.122.11-12)
- **LoadBalancer**: MetalLB with IP pool 192.168.122.100-150
- **GitOps**: ArgoCD using App-of-Apps pattern
- **Registry**: Harbor private container registry
- **CI/CD**: GitHub Actions with self-hosted runners (Actions Runner Controller)

## Common Commands

### Complete Deployment Workflow
```bash
# Phase 1: Host setup
./automation/scripts/setup-host.sh
# (logout/login required for group membership)
./automation/scripts/setup-storage.sh  
./automation/scripts/verify-setup.sh

# Phase 2: VM creation
cd automation/terraform && ./clean-and-deploy.sh

# Phase 3: Kubernetes cluster
cd ../ansible && ./k8s-deploy.sh

# Phase 4: Core infrastructure + Harbor cert fix + GitHub Actions (interactive)
cd ../phase4 && ./phase4-deploy.sh
# GitHub情報は対話式で入力またはスキップ可能

# または個別にGitHub Actions設定
./setup-arc.sh
```

### Operations & Troubleshooting
```bash
# VM management
sudo virsh list --all
sudo virsh console k8s-control-plane-X

# Cluster access
ssh k8suser@192.168.122.10
kubectl get nodes

# ArgoCD access (port-forward)
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Harbor access
kubectl port-forward svc/harbor-core -n harbor 8081:80
# Default: admin/Harbor12345

# Infrastructure status
kubectl get pods --all-namespaces
kubectl -n ingress-nginx get service ingress-nginx-controller  # LoadBalancer IP
kubectl get applications -n argocd  # ArgoCD sync status
```

### Testing & Verification
```bash
# Phase verification
./automation/scripts/verify-setup.sh  # Phase 1
terraform plan -out=tfplan  # Phase 2 (in terraform/)
kubectl get nodes  # Phase 3
kubectl get pods --all-namespaces | grep -E "(metallb|ingress|cert-manager|argocd)"  # Phase 4
```

## Key Directories

- **`automation/`**: All deployment automation (phases 1-4)
- **`infra/`**: Kubernetes manifests managed by ArgoCD (GitOps)
- **`app/`**: Application manifests for migrated services
- **`diagrams/`**: Architecture diagrams (SVG format)

## Important Files

### Configuration
- `automation/terraform/terraform.tfvars`: VM resource allocation
- `automation/ansible/inventory.ini`: Cluster node configuration  
- `infra/app-of-apps.yaml`: ArgoCD root application

### Certificates & Security
- `infra/cert-manager/harbor-certificate.yaml`: Harbor TLS with IP SAN
- `infra/harbor-ca-trust.yaml`: DaemonSet for CA trust distribution
- `automation/phase4/harbor-cert-fix.sh`: Fix Harbor certificate validation

### GitHub Actions
- `automation/phase4/github-actions-example.yml`: Self-hosted runner workflow
- Harbor registry integration with proper certificate handling

## Technologies

- **Infrastructure**: Terraform + libvirt, Ansible, kubeadm
- **Kubernetes**: v1.29.0, Flannel CNI, containerd runtime
- **Core Services**: MetalLB, NGINX Ingress, cert-manager, ArgoCD, Harbor
- **CI/CD**: GitHub Actions + Actions Runner Controller

## Development Notes

### GitOps Workflow
All infrastructure changes should be made through Git commits to trigger ArgoCD synchronization. The App-of-Apps pattern manages all applications from `infra/app-of-apps.yaml`.

### Resource Constraints  
VM resources are optimized for home lab environments:
- Control Plane: 4 CPU, 8GB RAM, 50GB disk
- Workers: 2 CPU, 4GB RAM, 30GB disk

### Network Configuration
- Host network: 192.168.122.0/24 (libvirt default)
- LoadBalancer pool: 192.168.122.100-150
- Services accessible via LoadBalancer IPs

### Harbor Certificate & GitHub Actions Integration
Harbor証明書修正とGitHub Actions対応は自動化済み：
- **Phase 4実行時**: `phase4-deploy.sh`で自動実行
- **ARC設定時**: `setup-arc.sh`で自動実行
- **手動実行**: `cd automation/phase4 && ./harbor-cert-fix.sh`

自動修正内容：
- IP SAN（192.168.122.100）を含むHarbor証明書生成
- CA信頼配布DaemonSet展開
- Worker ノードのinsecure registry設定
- GitHub Actions Runner自動再起動
- Harbor HTTP Ingress追加（フォールバック用）