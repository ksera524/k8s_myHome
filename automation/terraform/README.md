# Phase 2: VM構築（Terraform）

libvirtを使用してControl Plane 1台とWorker Node 2台のVMを自動構築します。

## 前提条件

Phase 1のセットアップが完了していることを確認してください：
```bash
../scripts/verify-setup.sh
```

## セットアップ手順

### 1. SSH鍵ペア生成
VM接続用のSSH鍵ペアを生成します：

```bash
# SSH鍵ペア生成（存在しない場合）
if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
fi

# 公開鍵の内容を確認
cat ~/.ssh/id_rsa.pub
```

### 2. Terraform設定
設定ファイルを作成します：

```bash
# 設定ファイルの作成
cp terraform.tfvars.example terraform.tfvars

# SSH公開鍵を設定ファイルに追加
echo "ssh_public_key = \"$(cat ~/.ssh/id_rsa.pub)\"" >> terraform.tfvars

# 設定内容を確認・編集
vim terraform.tfvars
```

### 3. libvirt providerのインストール
```bash
# Terraformの初期化
terraform init

# プランの確認
terraform plan

# VM構築の実行
terraform apply
```

## 構築されるリソース

### VM構成
- **Control Plane**: 4CPU, 8GB RAM, 50GB Disk
- **Worker Node 1**: 2CPU, 4GB RAM, 30GB Disk  
- **Worker Node 2**: 2CPU, 4GB RAM, 30GB Disk

### ネットワーク構成
- **Control Plane**: 192.168.122.10
- **Worker Node 1**: 192.168.122.11
- **Worker Node 2**: 192.168.122.12
- **Gateway**: 192.168.122.1 (ホストマシン)

### 自動インストール内容
各VMに以下が自動でインストール・設定されます：
- Ubuntu 22.04 LTS Server
- Docker CE
- kubeadm, kubelet, kubectl
- containerd（systemd cgroup設定済み）
- 必要なカーネルモジュール
- NFS共有のマウント設定

## VM接続方法

```bash
# 構築完了後、以下のコマンドでVMに接続可能
ssh k8suser@192.168.122.10  # Control Plane
ssh k8suser@192.168.122.11  # Worker Node 1
ssh k8suser@192.168.122.12  # Worker Node 2
```

## 構築状況の確認

### VM状態確認
```bash
# 全VMの状態確認
virsh list --all

# 個別VM状態確認
virsh dominfo k8s-control-plane
virsh dominfo k8s-worker1  
virsh dominfo k8s-worker2
```

### ネットワーク確認
```bash
# VM IPアドレス確認
virsh domifaddr k8s-control-plane
virsh domifaddr k8s-worker1
virsh domifaddr k8s-worker2

# 接続テスト
ping 192.168.122.10
ping 192.168.122.11  
ping 192.168.122.12
```

### cloud-init進行状況確認
```bash
# cloud-init完了まで待機
ssh k8suser@192.168.122.10 "sudo cloud-init status --wait"

# cloud-initログ確認
ssh k8suser@192.168.122.10 "sudo cat /var/log/cloud-init-output.log"
```

## 次の手順

VM構築完了後は、Phase 3（k8s構築）に進みます：

```bash
cd ../ansible
ansible-playbook -i inventory/hosts.yml playbook.yml
```

## トラブルシューティング

### よくある問題

1. **libvirt providerインストールエラー**
   ```bash
   # libvirt開発パッケージインストール
   sudo apt install -y libvirt-dev
   
   # Terraformプラグインキャッシュクリア
   rm -rf .terraform/
   terraform init
   ```

2. **VM起動エラー**
   ```bash
   # libvirtサービス確認
   sudo systemctl status libvirtd
   
   # デフォルトネットワーク確認
   virsh net-list --all
   virsh net-start default
   ```

3. **IPアドレス競合**
   ```bash
   # 使用中IPアドレス確認
   nmap -sn 192.168.122.0/24
   
   # terraform.tfvarsでIP変更
   ```

4. **SSH接続エラー**
   ```bash
   # VM起動完了まで待機
   while ! ping -c 1 192.168.122.10 >/dev/null 2>&1; do sleep 5; done
   
   # cloud-init完了まで待機
   ssh k8suser@192.168.122.10 "sudo cloud-init status --wait"
   ```

### ログ確認
```bash
# Terraformログ
export TF_LOG=DEBUG
terraform apply

# libvirtログ
sudo journalctl -u libvirtd

# VMコンソールログ
virsh console k8s-control-plane
```

### VM削除・再構築
```bash
# VM削除
terraform destroy

# 強制削除（必要に応じて）
virsh destroy k8s-control-plane
virsh undefine k8s-control-plane --remove-all-storage
```