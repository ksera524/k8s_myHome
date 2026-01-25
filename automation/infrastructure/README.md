# Phase 2: VM構築（Terraform）

libvirtを使用してControl Plane 1台とWorker Node 2台のVMを自動構築します。

## 概要

このディレクトリには、k8sクラスタ用のVM環境を自動構築するためのTerraformコードとスクリプトが含まれています。

### 重要な改善点

- ✅ **権限問題を完全解決**: AppArmor無効化 + libvirt権限修正
- ✅ **ネットワーク問題を完全解決**: ens3インターフェース対応
- ✅ **完全自動化**: 手動介入なしで確実に動作
- ✅ **エラー処理強化**: 包括的なエラーハンドリング

## 前提条件

Phase 1のセットアップが完了していることを確認してください：
```bash
../scripts/verify-setup.sh
```

## 🚀 推奨: ワンコマンド実行

**最も簡単で確実な方法:**

```bash
# 完全自動構築（推奨）
./clean-and-deploy-fixed.sh
```

このスクリプトが以下を自動実行します：
- 既存VM完全削除
- AppArmor無効化
- libvirt権限修正
- SSH鍵生成
- VM構築
- ネットワーク設定
- SSH接続テスト

## 📁 ファイル構成

```
automation/terraform/
├── main.tf                      # VM定義（改善済み）
├── variables.tf                 # 変数定義
├── outputs.tf                   # 出力定義
├── terraform.tfvars.example     # 設定例
├── clean-and-deploy-fixed.sh    # 🌟 メインスクリプト（推奨）
├── setup-terraform.sh           # 旧版（非推奨）
├── clean-and-deploy.sh          # 旧版（非推奨）
└── cloud-init/
    ├── user-data.yaml           # VM初期設定（パスワード認証対応）
    └── network-config.yaml      # ネットワーク設定（ens3対応）
```

## 構築されるリソース

### VM構成
| VM | CPU | RAM | Disk | IP |
|---|---|---|---|---|
| **Control Plane** | 4CPU | 8GB | 50GB | 192.168.122.10 |
| **Worker Node 1** | 2CPU | 4GB | 30GB | 192.168.122.11 |
| **Worker Node 2** | 2CPU | 4GB | 30GB | 192.168.122.12 |

### 自動設定内容
各VMに以下が自動で設定されます：
- **OS**: Ubuntu 22.04 LTS Server
- **ユーザー**: k8suser (password: `password`)
- **SSH**: 鍵認証 + パスワード認証
- **パッケージ**: curl, wget, git, vim, net-tools, nfs-common
- **ネットワーク**: 静的IP設定（ens3インターフェース）
- **NFS**: ホスト共有ストレージへの接続準備

## VM接続方法

構築完了後、以下の方法でVMに接続できます：

```bash
# SSH接続（推奨）
ssh k8suser@192.168.122.10  # Control Plane
ssh k8suser@192.168.122.11  # Worker Node 1  
ssh k8suser@192.168.122.12  # Worker Node 2

# コンソール接続（デバッグ用）
sudo virsh console k8s-control-plane-[ID]
# ログイン: k8suser / password
```

## 手動構築（上級者向け）

自動スクリプトを使わない場合の手順：

### 1. SSH鍵準備
```bash
# SSH鍵ペア生成（存在しない場合）
if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
fi
```

### 2. Terraform設定
```bash
# terraform.tfvars作成
cat > terraform.tfvars << EOF
vm_user = "k8suser"
ssh_public_key = "$(cat ~/.ssh/id_rsa.pub)"
control_plane_ip = "192.168.122.10"
worker_ips = ["192.168.122.11", "192.168.122.12"]
network_gateway = "192.168.122.1"
EOF
```

### 3. 権限問題の事前修正
```bash
# AppArmor無効化
sudo systemctl stop apparmor
sudo systemctl disable apparmor

# libvirt権限修正
echo 'security_driver = "none"' | sudo tee -a /etc/libvirt/qemu.conf
sudo systemctl restart libvirtd
```

### 4. VM構築実行
```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

## 構築状況の確認

### VM状態確認
```bash
# VM状態
sudo virsh list --all

# ネットワーク状態
sudo virsh net-dhcp-leases default

# 接続テスト
ping -c 3 192.168.122.10
ping -c 3 192.168.122.11
ping -c 3 192.168.122.12
```

### cloud-init進行状況
```bash
# cloud-init完了確認
ssh k8suser@192.168.122.10 'sudo cloud-init status --wait'

# cloud-initログ確認  
ssh k8suser@192.168.122.10 'sudo tail -f /var/log/cloud-init-output.log'
```

## 次のステップ

VM構築完了後は、Phase 3（k8s構築）に進みます：

```bash
cd ~/k8s_myHome/automation/ansible
# または
cd ../ansible

# k8s構築実行
ansible-playbook playbook.yml
```

## トラブルシューティング

### 最も確実な解決方法
```bash
# 完全リセット
./clean-and-deploy-fixed.sh
```

### 権限問題
```bash
# AppArmor確認
sudo aa-status | grep libvirt

# libvirt権限確認
sudo grep -E "^(user|group|security_driver)" /etc/libvirt/qemu.conf

# ファイル権限確認
ls -la /var/lib/libvirt/images/
```

### ネットワーク問題
```bash
# libvirtネットワーク確認
sudo virsh net-list --all
sudo virsh net-dumpxml default

# VM内ネットワーク確認
ssh k8suser@192.168.122.10 'ip addr show'
ssh k8suser@192.168.122.10 'sudo cat /etc/netplan/50-cloud-init.yaml'
```

### VM削除・再構築
```bash
# Terraform削除
terraform destroy -auto-approve

# 強制削除
sudo virsh list --all --name | grep k8s | xargs -I {} sudo virsh destroy {}
sudo virsh list --all --name | grep k8s | xargs -I {} sudo virsh undefine {} --remove-all-storage

# 完全クリーンアップ
./clean-and-deploy-fixed.sh
```

## サポート

問題が発生した場合：
1. まず `./clean-and-deploy-fixed.sh` で完全リセット
2. ログ確認: `sudo journalctl -u libvirtd -f`
3. VM状態確認: `sudo virsh list --all`
