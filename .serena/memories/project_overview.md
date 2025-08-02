# k8s_myHome プロジェクト概要

## プロジェクトの目的
- 本格的なホームKubernetesクラスタを構築・管理するためのIaC (Infrastructure as Code) プロジェクト
- k3sから本格的な3ノードクラスタへの移行
- 仮想化インフラストラクチャ上でのプロダクション級Home Lab環境

## 技術スタック
- **Kubernetes**: v1.29.0, kubeadm, containerd runtime, Flannel CNI
- **インフラ管理**: Terraform + libvirt (QEMU/KVM)
- **GitOps**: ArgoCD (App-of-Apps pattern)
- **コアサービス**: MetalLB, NGINX Ingress, cert-manager, Harbor
- **自動化**: Bash scripts, GitHub Actions + Actions Runner Controller
- **External Secrets**: External Secrets Operator (ESO) で秘密情報管理

## アーキテクチャ
- **Control Plane**: 1台 (192.168.122.10)
- **Worker Nodes**: 2台 (192.168.122.11-12)
- **LoadBalancer**: MetalLB (192.168.122.100-150)
- **Registry**: Harbor (192.168.122.100)
- **CI/CD**: GitHub Actions with self-hosted runners

## フェーズベースデプロイ
1. **Host Setup** (`automation/host-setup/`): Ubuntu 24.04 LTS ホスト準備
2. **Infrastructure** (`automation/infrastructure/`): VM + Kubernetesクラスタ構築
3. **Platform** (`automation/platform/`): コアプラットフォームサービス
4. **Applications** (`manifests/`): GitOps経由でのアプリケーション展開