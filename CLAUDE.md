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
4. **Applications** (`manifests/apps/`, `manifests/resources/applications/`): Application deployment via GitOps

### Key Infrastructure Components
- **Cluster**: 1 Control Plane (192.168.122.10) + 2 Workers (192.168.122.11-12)
- **LoadBalancer**: MetalLB with IP pool 192.168.122.100-150
- **GitOps**: ArgoCD using App-of-Apps pattern
- **Registry**: Harbor private container registry
- **CI/CD**: GitHub Actions with self-hosted runners (Actions Runner Controller)

## Common Commands

### Complete Deployment
```bash
# 完全なインフラストラクチャ構築
make all

# GitHub Actions Runnerを追加
make add-runner REPO=your-repository-name
```

### Manual Deployment Steps
```bash
# Host Setup: Host preparation
./automation/host-setup/setup-host.sh
# (logout/login required for group membership)
./automation/host-setup/setup-storage.sh  
./automation/host-setup/verify-setup.sh

# Infrastructure: VM creation + Kubernetes cluster
cd automation/infrastructure && ./clean-and-deploy.sh

# Platform: Core platform services + GitOps deployment
# 重要: settings.tomlの[Pulumi]セクションにaccess_tokenが必須
cd ../platform && ./platform-deploy.sh
# settings.tomlのリポジトリは自動でRunner追加されます
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
  - **`scripts/`**: Utility scripts
    - **`argocd/`**: ArgoCD management scripts
    - **`github-actions/`**: GitHub Actions runner scripts
  - **`templates/`**: Configuration templates
- **`manifests/`**: GitOps-specialized Kubernetes manifests
  - **`apps/`**: User application manifests
    - **`cloudflared/`**: Cloudflare tunnel
    - **`hitomi/`**: Hitomi downloader
    - **`pepup/`**: Pepup application
    - **`rss/`**: RSS reader
    - **`slack/`**: Slack bot
    - **`monitoring/`**: Grafana monitoring
  - **`bootstrap/applications/`**: Bootstrap ArgoCD applications
  - **`config/secrets/`**: External Secrets Operator configurations
  - **`core/`**: Core cluster resources
    - **`namespaces/`**: Namespace definitions
    - **`storage-classes/`**: Storage class configurations
  - **`infrastructure/`**: Infrastructure components
    - **`gitops/harbor/`**: Harbor GitOps patches
    - **`networking/metallb/`**: MetalLB load balancer
    - **`security/cert-manager/`**: Certificate management
  - **`platform/`**: Platform services
    - **`argocd-config/`**: ArgoCD configurations
    - **`ci-cd/github-actions/`**: GitHub Actions runner configs
    - **`secrets/external-secrets/`**: External Secrets Operator
  - **`monitoring/`**: Monitoring stack configurations
  - **`resources/`**: Legacy resource directory (migration in progress)
- **`docs/`**: Project documentation

## Important Files

### Configuration
- `automation/settings.toml.example`: Main configuration template
- `automation/infrastructure/terraform.tfvars`: VM resource allocation
- `automation/infrastructure/main.tf`: Infrastructure as Code definition
- `manifests/bootstrap/applications/app-of-apps.yaml`: ArgoCD root application

### Deployment Scripts
- `automation/scripts/run.sh`: Main automation entry point
- `automation/platform/platform-deploy.sh`: Platform deployment script
- `automation/scripts/github-actions/setup-arc.sh`: GitHub Actions Runner setup
- `automation/scripts/github-actions/add-runner.sh`: Add new GitHub runner

### Certificates & Security
- `manifests/infrastructure/security/cert-manager/`: Certificate management configs
- `manifests/config/secrets/`: External Secrets configurations
- `automation/platform/harbor-cert-fix.sh`: Fix Harbor certificate validation

### GitHub Actions
- `automation/scripts/github-actions/`: Runner management scripts
- `manifests/platform/ci-cd/github-actions/`: ARC configurations
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
All infrastructure changes should be made through Git commits to trigger ArgoCD synchronization. The App-of-Apps pattern manages all applications from `manifests/00-bootstrap/app-of-apps.yaml`.

### Resource Constraints  
VM resources are optimized for home lab environments:
- Control Plane: 4 CPU, 8GB RAM, 50GB disk
- Workers: 2 CPU, 4GB RAM, 30GB disk

### Network Configuration
- Host network: 192.168.122.0/24 (libvirt default)
- LoadBalancer pool: 192.168.122.100-150
- Services accessible via LoadBalancer IPs

### Harbor & GitHub Actions Integration
HarborとGitHub Actions Runner Controller (ARC) の統合:
- **GitOps管理**: ARC ControllerはArgoCD経由でHelm chartをデプロイ
- **認証**: GitHub PATはExternal Secrets Operator経由で`github`キーから取得
- **自動Runner追加**: `make all`時にsettings.tomlのリポジトリが自動追加
- **個別追加**: `make add-runner REPO=repository-name`

Runner設定:
- minRunners=1（推奨）: 常時1つのRunnerを起動
- maxRunners=3: 最大3つまでスケール
- Docker-in-Docker対応
- skopeoによるHarbor push（TLS検証無効）
