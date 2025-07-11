# k3sからk8sへの移行計画

## 概要
現在のk3sクラスタから、VM上にフルk8sクラスタを構築して移行する計画

## 現在の構成
- ホストマシン: k3s（シングルノード）
- アプリケーション: factorio, cloudflared, hitomi, pepup, rss, s3s, slack（7つ）
- インフラ: ArgoCD, Argo Workflow, cert-manager, harbor
- ストレージ: 外部SSD（/mnt/external-ssd）
- CI/CD: Argo Workflow

## 移行先の要件
- ホストマシン: Ubuntu 24.04 LTS
- 仮想化: QEMU/KVM + libvirt
- k8s構成: Control Plane 1台 + Worker Node 2台
- ストレージ: USB外部ストレージをk8s上で活用
- CI/CD: GitHub Actions Self-hosted Runner
- Secret管理: リポジトリベース
- 自動化: コード化・再現可能

## 移行計画（5段階）

### Phase 1: 各種アプリケーションinstall
#### 1.1 ホストマシン準備（Ubuntu 24.04 LTS）
- 必要なパッケージインストール
  ```bash
  # 仮想化関連
  sudo apt update
  sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst virt-manager
  
  # その他ツール
  sudo apt install -y git curl wget ansible terraform
  ```

#### 1.2 ユーザー権限設定
- libvirtグループへの追加
  ```bash
  sudo usermod -aG libvirt $USER
  sudo usermod -aG kvm $USER
  ```

#### 1.3 外部ストレージ設定
- USB外部ストレージのマウント設定
- fstabでの永続化設定

### Phase 2: VM構築
#### 2.1 VM作成自動化（Terraform + libvirt provider）
- Control Plane VM: 4CPU, 8GB RAM, 50GB disk
- Worker Node VM x2: 2CPU, 4GB RAM, 30GB disk
- ネットワーク: NAT + Bridge設定

#### 2.2 VM設定
- Ubuntu 22.04 LTS Server
- SSH鍵ベース認証
- 静的IPアドレス設定
- ホスト名設定

#### 2.3 ストレージ設定
- 外部USBストレージを各VMにマウント
- NFS共有設定（Control PlaneでNFSサーバー構築）

### Phase 3: k8s構築
#### 3.1 kubeadm使用によるクラスタ構築
- Container Runtime: containerd
- CNI: Flannel or Calico
- kubeadm init（Control Plane）
- kubeadm join（Worker Nodes）

#### 3.2 ストレージクラス設定
- NFS StorageClass
- Local StorageClass（高速アクセス用）
- PersistentVolume/PersistentVolumeClaim設定

#### 3.3 基本インフラ構築
- MetalLB（LoadBalancer）
- Ingress Controller（NGINX）
- cert-manager
- Harbor（プライベートレジストリ）

### Phase 4: CI/CD構築
#### 4.1 GitHub Actions Self-hosted Runner
- k8s上でRunner Pod構築
- Autoscaling設定
- Secret管理（GitHub App）

#### 4.2 CI/CDパイプライン設計
- Docker Build & Push
- k8s Deployment
- Testing & Linting
- Rollback機能

#### 4.3 既存Argo Workflowからの移行
- Workflow定義をGitHub Actions形式に変換
- Event-driven triggers設定

### Phase 5: Secret管理
#### 5.1 Secret管理方式
- 暗号化されたSecretファイルをリポジトリで管理
- kubectl create secret + gpg暗号化
- または、External Secrets Operator + HashiCorp Vault

#### 5.2 Secret自動デプロイ
- GitOps方式でSecret更新
- CI/CDパイプラインでの自動適用

## アプリケーション移行計画

### 移行順序
1. **factorio**: ストレージ依存度が高いため先行移行
2. **cloudflared**: ネットワーク設定確認用
3. **slack**: Harbor連携確認用
4. **rss, s3s, pepup, hitomi**: 残りのアプリケーション

### 各アプリケーション移行ポイント
- **factorio**: 外部ストレージ直接マウント → NFS共有に変更
- **cloudflared**: Secret管理方式変更
- **slack**: Harbor参照設定変更
- その他: NodePort → LoadBalancer/Ingress設定

## 自動化スクリプト構成
```
automation/
├── terraform/          # VM構築
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── ansible/            # k8s構築
│   ├── playbook.yml
│   ├── inventory/
│   └── roles/
├── k8s/                # k8s manifests
│   ├── infrastructure/
│   ├── applications/
│   └── secrets/
└── scripts/            # 各種スクリプト
    ├── setup-host.sh
    ├── deploy-k8s.sh
    └── migrate-apps.sh
```

## 実行手順
1. `./scripts/setup-host.sh` - ホスト環境セットアップ
2. `cd terraform && terraform apply` - VM構築
3. `cd ansible && ansible-playbook playbook.yml` - k8s構築
4. `./scripts/deploy-k8s.sh` - インフラ構築
5. `./scripts/migrate-apps.sh` - アプリケーション移行

## 検証項目
- [ ] VM正常起動・ネットワーク疎通
- [ ] k8sクラスタ正常動作
- [ ] ストレージ読み書き
- [ ] 各アプリケーション正常動作
- [ ] CI/CD パイプライン動作
- [ ] Secret管理動作
- [ ] 障害時の自動復旧

## 注意事項
- k3s環境からのデータバックアップは不要（要件8）
- 移行期間中は一時的にサービス停止
- 外部ストレージのマウントポイント変更に注意
- GitHub Actions無料枠の使用量に注意