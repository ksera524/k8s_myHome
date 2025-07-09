# k3sからKubernetesクラスターへの移行計画

## 概要
このドキュメントは、現在のk3s単一ノード環境から、QEMU/KVM上の3台VM構成によるKubernetesクラスターへの移行計画を記述します。

## 現在の構成分析

### 現環境
- **プラットフォーム**: k3s単一ノード（ksera-t100）
- **アプリケーション**: 
  - Factorio
  - Slack
  - CloudFlare
  - Hitomi
  - Pepup
  - RSS
  - S3S
- **ストレージ**: 3.4TB USB外部SSD（/mnt/external-ssd）
- **インフラコンポーネント**: 
  - ArgoCD
  - Argo Workflow
  - Harbor
  - Cert-Manager
- **管理ツール**: Terraform + Helm

### 現在の課題
- 単一ノード構成による可用性の問題
- Argo Workflowの制約
- Secret管理の課題

## 移行要件

1. **VM基盤**: QEMU/KVM + libvirtを使用した仮想化
2. **クラスター構成**: Control Plane 1台 + Worker Node 2台
3. **ストレージ**: USB外部ストレージの効率的な統合
4. **CI/CD**: Argo Workflow → GitHub Actions Self-hosted Runner
5. **Secret管理**: リポジトリベースの暗号化Secret管理
6. **自動化**: Infrastructure as Codeによる完全自動化

## 1. VM基盤構築（QEMU/KVM + libvirt）

### 必要なパッケージのインストール
```bash
# libvirt + QEMU/KVM セットアップ
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager
```

### Terraformプロバイダー設定
```hcl
terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.1"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}
```

### VM仕様
- **Control Plane**: 4vCPU, 8GB RAM, 100GB disk
- **Worker Node 1**: 4vCPU, 8GB RAM, 100GB disk  
- **Worker Node 2**: 4vCPU, 8GB RAM, 100GB disk

### VM作成用Terraformリソース例
```hcl
resource "libvirt_domain" "k8s_control_plane" {
  name   = "k8s-control-plane"
  memory = "8192"
  vcpu   = 4

  disk {
    volume_id = libvirt_volume.k8s_control_plane.id
  }

  network_interface {
    network_name = "default"
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}
```

## 2. Kubernetesクラスター構築

### kubeadmによる自動化セットアップ

#### Control Plane初期化
```bash
# Control Plane初期化
kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=<CONTROL_PLANE_IP> \
  --control-plane-endpoint=<CONTROL_PLANE_IP>:6443
```

#### Worker Node参加
```bash
# Worker Node参加
kubeadm join <CONTROL_PLANE_IP>:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash <HASH>
```

### CNI（Container Network Interface）
**選択**: Flannel（設定済みPod CIDRと互換）

```bash
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```

### Ansibleによる自動化
```yaml
# playbooks/k8s-setup.yml
---
- name: Setup Kubernetes Cluster
  hosts: k8s_nodes
  become: yes
  tasks:
    - name: Install Docker
      apt:
        name: docker.io
        state: present

    - name: Install kubeadm, kubelet, kubectl
      apt:
        name: "{{ item }}"
        state: present
      loop:
        - kubeadm
        - kubelet
        - kubectl

    - name: Initialize control plane
      shell: kubeadm init --pod-network-cidr=10.244.0.0/16
      when: inventory_hostname in groups['control_plane']

    - name: Join worker nodes
      shell: "{{ hostvars[groups['control_plane'][0]]['join_command'] }}"
      when: inventory_hostname in groups['workers']
```

## 3. USB外部ストレージ統合

### NFS Server + CSI Driver方式

#### NFS Server設定
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-server
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nfs-server
  template:
    metadata:
      labels:
        app: nfs-server
    spec:
      nodeSelector:
        kubernetes.io/hostname: k8s-control-plane
      containers:
      - name: nfs-server
        image: itsthenetwork/nfs-server-alpine:latest
        ports:
        - name: nfs
          containerPort: 2049
        - name: mountd
          containerPort: 20048
        - name: rpcbind
          containerPort: 111
        securityContext:
          privileged: true
        volumeMounts:
        - name: external-storage
          mountPath: /exports
        env:
        - name: SHARED_DIRECTORY
          value: "/exports"
      volumes:
      - name: external-storage
        hostPath:
          path: /mnt/external-ssd
          type: Directory
```

#### NFS CSI Driver
```bash
# NFS CSI Driver インストール
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs --namespace kube-system
```

#### StorageClass定義
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-external
provisioner: nfs.csi.k8s.io
parameters:
  server: <NFS_SERVER_IP>
  share: /exports
  mountPermissions: "0755"
reclaimPolicy: Retain
volumeBindingMode: Immediate
```

## 4. GitHub Actions Self-hosted Runner

### Argo Workflow → GitHub Actions移行

#### GitHub Actions Runner Deployment
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: github-runner
  namespace: ci-cd
spec:
  replicas: 2
  selector:
    matchLabels:
      app: github-runner
  template:
    metadata:
      labels:
        app: github-runner
    spec:
      containers:
      - name: runner
        image: myoung34/github-runner:latest
        env:
        - name: REPO_URL
          value: "https://github.com/yourusername/k8s_myHome"
        - name: RUNNER_NAME
          value: "k8s-runner"
        - name: RUNNER_TOKEN
          valueFrom:
            secretKeyRef:
              name: github-secrets
              key: runner-token
        - name: RUNNER_WORKDIR
          value: "/tmp/github-runner"
        - name: RUNNER_GROUP
          value: "default"
        - name: LABELS
          value: "kubernetes,self-hosted"
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        volumeMounts:
        - name: docker-sock
          mountPath: /var/run/docker.sock
        - name: runner-tmp
          mountPath: /tmp/github-runner
      volumes:
      - name: docker-sock
        hostPath:
          path: /var/run/docker.sock
      - name: runner-tmp
        emptyDir: {}
```

#### GitHub Actions Workflow例
```yaml
# .github/workflows/deploy.yml
name: Deploy to Kubernetes

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  deploy:
    runs-on: [self-hosted, kubernetes]
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup kubectl
      uses: azure/setup-kubectl@v3
      with:
        version: 'latest'
    
    - name: Deploy to cluster
      run: |
        kubectl apply -f app/*/manifest.yaml
        kubectl rollout status deployment/slack -n sandbox
```

## 5. Secret管理

### Sealed Secrets使用

#### Controller導入
```bash
# Sealed Secrets Controller導入
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.18.0/controller.yaml

# kubeseal CLI インストール
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.18.0/kubeseal-0.18.0-linux-amd64.tar.gz
tar -xvzf kubeseal-0.18.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

#### Secret暗号化例
```bash
# 通常のSecretを作成
kubectl create secret generic slack-secret \
  --from-literal=token=your-slack-token \
  --dry-run=client -o yaml > slack-secret.yaml

# Sealed Secretに変換
kubeseal -f slack-secret.yaml -w slack-sealed-secret.yaml

# 元のSecretファイルを削除
rm slack-secret.yaml
```

#### リポジトリ構造
```
secrets/
├── slack-sealed.yaml
├── harbor-sealed.yaml
├── github-sealed.yaml
└── README.md
```

### Secret管理用Kustomization
```yaml
# secrets/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- slack-sealed.yaml
- harbor-sealed.yaml
- github-sealed.yaml

namespace: default
```

## 6. Infrastructure as Code

### Terraformモジュール構造
```
terraform/
├── modules/
│   ├── vm/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── k8s/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── storage/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── environments/
│   └── production/
│       ├── main.tf
│       ├── variables.tf
│       └── terraform.tfvars
└── main.tf
```

### メインTerraform設定
```hcl
# terraform/main.tf
terraform {
  required_version = ">= 1.0"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0.0"
    }
  }
}

module "vm_infrastructure" {
  source = "./modules/vm"
  
  control_plane_count = 1
  worker_node_count   = 2
  vm_memory          = 8192
  vm_vcpu            = 4
}

module "kubernetes_cluster" {
  source = "./modules/k8s"
  
  depends_on = [module.vm_infrastructure]
  
  cluster_name = "k8s-home"
  pod_cidr     = "10.244.0.0/16"
  service_cidr = "10.96.0.0/12"
}

module "storage_integration" {
  source = "./modules/storage"
  
  depends_on = [module.kubernetes_cluster]
  
  external_storage_path = "/mnt/external-ssd"
  nfs_server_ip        = module.vm_infrastructure.control_plane_ip
}
```

### Ansibleインベントリ自動生成
```yaml
# ansible/inventory/hosts.yml
all:
  children:
    k8s_cluster:
      children:
        control_plane:
          hosts:
            k8s-control-plane:
              ansible_host: "{{ terraform_output.control_plane_ip }}"
        workers:
          hosts:
            k8s-worker-1:
              ansible_host: "{{ terraform_output.worker_1_ip }}"
            k8s-worker-2:
              ansible_host: "{{ terraform_output.worker_2_ip }}"
      vars:
        ansible_user: ubuntu
        ansible_ssh_private_key_file: ~/.ssh/k8s_key
```

## 7. 移行ロードマップ

### Phase 1: 基盤構築（週1-2）
#### 目標
- QEMU/KVM環境の構築と設定
- VM作成の自動化
- 基本的なKubernetesクラスターの構築

#### タスク
1. **Week 1**
   - [ ] ホストマシンにQEMU/KVM + libvirtをインストール
   - [ ] Terraformプロバイダーの設定と動作確認
   - [ ] VM作成用Terraformモジュールの作成
   - [ ] 3台のVM（Control Plane 1台、Worker 2台）の作成

2. **Week 2**
   - [ ] Ansibleプレイブックの作成
   - [ ] kubeadmを使用したKubernetesクラスターの初期化
   - [ ] CNI（Flannel）の導入
   - [ ] 基本的なクラスター動作確認

#### 成果物
- 動作するKubernetesクラスター
- VM作成・管理用Terraformコード
- クラスター構築用Ansibleプレイブック

### Phase 2: ストレージ・CI/CD（週3-4）
#### 目標
- USB外部ストレージの統合
- GitHub Actions Self-hosted Runnerの構築
- 基本的なCI/CDパイプラインの動作確認

#### タスク
1. **Week 3**
   - [ ] NFS Serverの構築と設定
   - [ ] NFS CSI Driverの導入
   - [ ] StorageClassの作成と動作確認
   - [ ] 既存アプリケーション用PVCの作成

2. **Week 4**
   - [ ] GitHub Actions Self-hosted Runnerの構築
   - [ ] Argo Workflowからの移行計画策定
   - [ ] 基本的なCI/CDワークフローの作成
   - [ ] Secret管理システム（Sealed Secrets）の導入

#### 成果物
- 統合されたストレージシステム
- 動作するGitHub Actions Runner
- 基本的なCI/CDパイプライン

### Phase 3: アプリケーション移行（週5-6）
#### 目標
- 既存アプリケーションの新クラスターへの移行
- DNS・ネットワーク設定の調整
- 全アプリケーションの動作確認

#### タスク
1. **Week 5**
   - [ ] 既存アプリケーションマニフェストの新クラスター用更新
   - [ ] Factorio, Slack等の段階的移行
   - [ ] Harbor, ArgoCD等のインフラコンポーネント移行
   - [ ] ネットワーク設定の調整

2. **Week 6**
   - [ ] 全アプリケーションの動作確認
   - [ ] パフォーマンステストの実施
   - [ ] 旧k3s環境からの完全切り替え
   - [ ] DNS設定の更新

#### 成果物
- 全アプリケーションが動作する新Kubernetesクラスター
- 更新されたアプリケーションマニフェスト
- 動作確認済みのサービス

### Phase 4: 運用・監視（週7-8）
#### 目標
- 監視・ログ収集システムの構築
- バックアップ戦略の実装
- ドキュメントの整備

#### タスク
1. **Week 7**
   - [ ] Prometheus + Grafanaによる監視システム構築
   - [ ] ログ収集システム（ELK Stack等）の導入
   - [ ] アラート設定の構築
   - [ ] リソース使用量の最適化

2. **Week 8**
   - [ ] 自動バックアップシステムの構築
   - [ ] 災害復旧手順の作成
   - [ ] 運用ドキュメントの整備
   - [ ] 移行完了後の検証とレビュー

#### 成果物
- 完全な監視・ログ収集システム
- バックアップ・復旧システム
- 運用ドキュメント一式

## 8. 設定ファイル例

### Docker Compose（開発環境用）
```yaml
# docker-compose.yml
version: '3.8'
services:
  libvirt:
    image: libvirt/libvirt:latest
    privileged: true
    volumes:
      - /var/run/libvirt:/var/run/libvirt
      - /sys/fs/cgroup:/sys/fs/cgroup:ro
    
  terraform:
    image: hashicorp/terraform:latest
    volumes:
      - .:/workspace
    working_dir: /workspace
    command: ["terraform", "plan"]
```

### GitHub Actions Runner設定
```bash
#!/bin/bash
# scripts/setup-runner.sh

# GitHub Runner設定スクリプト
REPO_URL="https://github.com/yourusername/k8s_myHome"
RUNNER_TOKEN="${GITHUB_RUNNER_TOKEN}"

# Runner設定
./config.sh \
  --url "${REPO_URL}" \
  --token "${RUNNER_TOKEN}" \
  --name "k8s-home-runner" \
  --labels "kubernetes,self-hosted,linux,x64" \
  --work "_work" \
  --replace

# Runner起動
./run.sh
```

## 9. 運用・保守

### 定期メンテナンス
```bash
# scripts/maintenance.sh
#!/bin/bash

# Kubernetesクラスター健全性チェック
kubectl get nodes
kubectl get pods --all-namespaces
kubectl top nodes
kubectl top pods --all-namespaces

# ストレージ使用量チェック
df -h /mnt/external-ssd

# バックアップ実行
kubectl create backup cluster-backup-$(date +%Y%m%d)
```

### 監視・アラート設定
```yaml
# monitoring/alerts.yml
groups:
- name: kubernetes-cluster
  rules:
  - alert: NodeDown
    expr: up{job="kubernetes-nodes"} == 0
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "Node {{ $labels.instance }} is down"
      
  - alert: PodCrashLooping
    expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Pod {{ $labels.pod }} is crash looping"
```

## 10. トラブルシューティング

### よくある問題と解決策

#### VM作成時の問題
```bash
# libvirt権限問題
sudo usermod -a -G libvirt $USER
sudo systemctl restart libvirtd

# ネットワーク接続問題
sudo virsh net-start default
sudo virsh net-autostart default
```

#### Kubernetesクラスター問題
```bash
# ノード参加失敗
kubeadm token create --print-join-command

# CNI問題
kubectl delete -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```

#### ストレージ関連問題
```bash
# NFS接続問題
showmount -e <NFS_SERVER_IP>
sudo mount -t nfs <NFS_SERVER_IP>:/exports /mnt/test

# PVC作成問題
kubectl describe pvc <PVC_NAME>
kubectl get events --sort-by=.metadata.creationTimestamp
```

## 11. 参考資料

### 公式ドキュメント
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [libvirt Documentation](https://libvirt.org/docs.html)
- [Terraform libvirt Provider](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Sealed Secrets Documentation](https://sealed-secrets.netlify.app/)

### 参考リポジトリ
- [kubeadm Installation Guide](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [NFS CSI Driver](https://github.com/kubernetes-csi/csi-driver-nfs)
- [GitHub Actions Self-hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)

---

この移行計画により、現在のk3s環境から完全に自動化されたKubernetesクラスターに段階的に移行することができます。各フェーズでの成果物を確実に作成し、次のフェーズに進むことで、安全かつ確実な移行を実現できます。