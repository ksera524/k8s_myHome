# CLAUDE.md
必ず日本語で応答し、コメントも日本語で書いて
k8s manifestはmamifests配下を利用すること

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**k8s_myHome** is a production-grade home Kubernetes infrastructure project that migrates from k3s to a full 3-node cluster on virtualized infrastructure. The codebase is primarily documented in Japanese and uses a phase-based deployment approach with complete automation.

## Architecture

### Deployment Components (Execute in Order)
1. **Host Setup** (`automation/host-setup/`): Host preparation - Ubuntu 24.04 LTS setup
2. **Infrastructure** (`automation/infrastructure/`): VM infrastructure + Kubernetes cluster - QEMU/KVM with libvirt + kubeadm-based 3-node cluster (統合実装)
3. **Platform** (`automation/platform/`): Core platform services - MetalLB, NGINX, cert-manager, ArgoCD, Harbor
4. **Applications** (`manifests/`, `app/`): Application deployment via GitOps

### Key Infrastructure Components
- **Cluster**: 1 Control Plane (192.168.122.10) + 2 Workers (192.168.122.11-12)
- **LoadBalancer**: MetalLB with IP pool 192.168.122.100-150
- **GitOps**: ArgoCD using App-of-Apps pattern
- **Registry**: Harbor private container registry
- **CI/CD**: GitHub Actions with self-hosted runners (Actions Runner Controller)

## Common Commands

### Complete Deployment Workflow
```bash
# Host Setup: Host preparation
./automation/host-setup/setup-host.sh
# (logout/login required for group membership)
./automation/host-setup/setup-storage.sh  
./automation/host-setup/verify-setup.sh

# Infrastructure: VM creation + Kubernetes cluster
cd automation/infrastructure && ./clean-and-deploy.sh
# VM構築とKubernetesクラスター構築が統合され、1つのコマンドで完了

# Platform: Core platform services + Harbor cert fix + GitHub Actions (interactive)
cd ../platform && ./phase4-deploy.sh
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
# Component verification
./automation/host-setup/verify-setup.sh  # Host Setup
terraform plan -out=tfplan  # Infrastructure検証 (in infrastructure/)
ssh k8suser@192.168.122.10 'kubectl get nodes'  # Infrastructure結果確認
kubectl get pods --all-namespaces | grep -E "(metallb|ingress|cert-manager|argocd)"  # Platform
```

## Key Directories

- **`automation/`**: All deployment automation
  - **`host-setup/`**: Host preparation scripts
  - **`infrastructure/`**: VM infrastructure + Kubernetes cluster (Terraform統合実装)
  - **`platform/`**: Core platform services (MetalLB, NGINX, cert-manager, ArgoCD, Harbor)
- **`manifests/`**: Organized Kubernetes manifests for all components
  - **`infrastructure/`**: Core infrastructure (ArgoCD, MetalLB, cert-manager, Harbor, etc.)
  - **`applications/`**: User applications (RSS, Hitomi, Pepup, Cloudflared, Slack)
  - **`external-secrets/`**: External Secrets Operator and configurations  
  - **`platform/`**: Platform services (GitHub Actions, monitoring)
- **`diagrams/`**: Architecture diagrams (SVG format)

## Important Files

### Configuration
- `automation/infrastructure/terraform.tfvars`: VM resource allocation
- `manifests/app-of-apps.yaml`: ArgoCD root application

### Certificates & Security
- `manifests/infrastructure/cert-manager/harbor-certificate.yaml`: Harbor TLS with IP SAN
- `manifests/infrastructure/harbor-ca-trust.yaml`: DaemonSet for CA trust distribution
- `automation/platform/harbor-cert-fix.sh`: Fix Harbor certificate validation

### GitHub Actions
- `automation/platform/github-actions-example.yml`: Self-hosted runner workflow
- Harbor registry integration with proper certificate handling

## Technologies

- **Infrastructure**: Terraform + libvirt, kubeadm (Ansible統合完了)
- **Kubernetes**: v1.29.0, Flannel CNI, containerd runtime
- **Core Services**: MetalLB, NGINX Ingress, cert-manager, ArgoCD, Harbor
- **CI/CD**: GitHub Actions + Actions Runner Controller

## Migration Notes

**2025-01-23**: 構成要素名の機能ベース化とAnsible統合完了
- Phase名からhost-setup/infrastructure/platformの機能ベース名に変更
- AnsibleのKubernetesクラスター構築をTerraformに統合し、infrastructureコンポーネントとして実装
- 詳細は `docs/terraform-ansible-migration-report.md` を参照

## Development Notes

### GitOps Workflow
All infrastructure changes should be made through Git commits to trigger ArgoCD synchronization. The App-of-Apps pattern manages all applications from `manifests/app-of-apps.yaml`.

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