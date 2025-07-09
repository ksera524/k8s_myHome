# Kubernetes Cluster Migration Project

このプロジェクトは、現在のk3s環境から新しいKubernetesクラスター（3台VM構成）への移行を自動化します。

## 📁 プロジェクト構造

```
k8s_myHome/
├── migration-plan.md                # 詳細な移行計画書
├── README-migration.md              # このファイル
├── terraform-new/                   # VM基盤用Terraform
│   ├── main.tf
│   └── modules/
│       ├── vm/                      # VM作成モジュール
│       ├── k8s/                     # Kubernetes設定
│       └── storage/                 # ストレージ統合
├── ansible/                         # クラスター構築用Ansible
│   ├── inventory/hosts.yml
│   ├── playbooks/site.yml
│   └── roles/
├── k8s-manifests/                   # 新クラスター用マニフェスト
│   ├── infrastructure/
│   └── applications/
├── secrets/                         # Sealed Secrets管理
│   ├── README.md
│   └── examples/create-secrets.sh
├── .github/workflows/               # GitHub Actions
│   ├── deploy.yml
│   └── infrastructure.yml
└── scripts/                         # 自動化スクリプト
    ├── setup/
    ├── maintenance/
    └── migration/
```

## 🚀 クイックスタート

### 1. 前提条件のインストール
```bash
# 必要なツールをすべてインストール
./scripts/setup/install-prerequisites.sh

# 再ログイン（libvirtグループ適用のため）
logout
```

### 2. 既存k3s環境のバックアップ
```bash
# k3sからのデータとマニフェストをバックアップ
./scripts/migration/migrate-from-k3s.sh
```

### 3. 新しいクラスターのデプロイ
```bash
# 完全自動でクラスターを構築
./scripts/setup/deploy-cluster.sh
```

### 4. Secretsの設定
```bash
# Sealed Secretsを作成
./secrets/examples/create-secrets.sh
```

### 5. アプリケーションのデプロイ
```bash
# GitHub Actions経由、または手動で
kubectl apply -f k8s-manifests/applications/
```

## 🔧 主要コンポーネント

### VM基盤 (QEMU/KVM + libvirt)
- **Control Plane**: 1台 (4vCPU, 8GB RAM)
- **Worker Nodes**: 2台 (各4vCPU, 8GB RAM)
- **ストレージ**: 各100GB + 外部USB SSD統合

### Kubernetesクラスター
- **Container Runtime**: Docker
- **CNI**: Flannel
- **Storage**: NFS CSI Driver
- **Secret管理**: Sealed Secrets

### CI/CD
- **Argo Workflow** → **GitHub Actions Self-hosted Runners**
- **自動デプロイ**: マニフェスト変更時に自動実行
- **品質保証**: Linting, Validation, Health Check

## 📋 移行手順

### Phase 1: 基盤構築 (週1-2)
```bash
# 1. 前提条件インストール
./scripts/setup/install-prerequisites.sh

# 2. VM基盤デプロイ
cd terraform-new
terraform init
terraform plan
terraform apply

# 3. Kubernetesクラスター構築
cd ../ansible
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

### Phase 2: ストレージ・CI/CD (週3-4)
```bash
# 1. NFS統合とStorageClass設定
kubectl apply -f k8s-manifests/infrastructure/nfs-storage.yaml

# 2. GitHub Actions Runner構築
kubectl apply -f k8s-manifests/infrastructure/github-runner.yaml

# 3. Sealed Secrets設定
./secrets/examples/create-secrets.sh
```

### Phase 3: アプリケーション移行 (週5-6)
```bash
# 1. データ移行
# バックアップディレクトリのmigrate-data.shを実行

# 2. アプリケーションデプロイ
kubectl apply -f k8s-manifests/applications/

# 3. 動作確認
./scripts/maintenance/cluster-health-check.sh
```

### Phase 4: 運用・監視 (週7-8)
- Prometheus + Grafana導入
- ログ収集システム構築
- バックアップ戦略実装

## 🛠️ 運用・保守

### ヘルスチェック
```bash
# 包括的なクラスター健全性チェック
./scripts/maintenance/cluster-health-check.sh
```

### リソース監視
```bash
# ノードリソース確認
kubectl top nodes

# Podリソース確認
kubectl top pods --all-namespaces
```

### バックアップ
```bash
# etcdバックアップ
kubectl get all --all-namespaces -o yaml > cluster-backup.yaml

# Sealed Secretsキーバックアップ
kubectl get secret -n kube-system sealed-secrets-key -o yaml > sealed-secrets-key-backup.yaml
```

## 🔐 セキュリティ

### Secret管理
- **Sealed Secrets**: GitOpsフレンドリーな暗号化Secret管理
- **平文Secret禁止**: リポジトリに平文Secretは保存不可
- **定期ローテーション**: Secret定期更新の実装

### ネットワークセキュリティ
- **NodePort制限**: 必要最小限のポート公開
- **NetworkPolicy**: Pod間通信制御（必要に応じて）
- **TLS終端**: Harbor等でのTLS設定

## 📊 監視・ログ

### 推奨監視スタック
```bash
# Prometheus + Grafana
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack

# ログ収集 (ELK Stack)
helm repo add elastic https://helm.elastic.co
helm install elasticsearch elastic/elasticsearch
helm install kibana elastic/kibana
helm install filebeat elastic/filebeat
```

## 🚨 トラブルシューティング

### よくある問題

#### VM作成失敗
```bash
# libvirt権限確認
sudo usermod -a -G libvirt $USER
sudo systemctl restart libvirtd

# ネットワーク確認
sudo virsh net-start default
```

#### クラスター接続問題
```bash
# kubectl設定確認
kubectl config view
kubectl cluster-info

# ノード状態確認
kubectl get nodes -o wide
```

#### ストレージ問題
```bash
# NFS接続確認
showmount -e <NFS_SERVER_IP>

# PVC状態確認
kubectl get pvc --all-namespaces
kubectl describe pvc <PVC_NAME>
```

## 📞 サポート

### ログ収集
問題発生時は以下のログを収集してください：

```bash
# クラスター状態
kubectl get all --all-namespaces -o wide > cluster-state.log

# イベント
kubectl get events --all-namespaces --sort-by='.lastTimestamp' > events.log

# ノードログ
journalctl -u kubelet > kubelet.log
```

### GitHub Issues
問題や改善提案は GitHub Issues で報告してください。

---

## 📚 参考資料

- [Kubernetes公式ドキュメント](https://kubernetes.io/docs/)
- [Terraform libvirtプロバイダー](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs)
- [Ansible公式ドキュメント](https://docs.ansible.com/)
- [Sealed Secrets](https://sealed-secrets.netlify.app/)
- [GitHub Actions](https://docs.github.com/en/actions)

この移行プロジェクトにより、現在のk3s環境から完全に自動化されたKubernetesクラスターに安全かつ確実に移行できます。