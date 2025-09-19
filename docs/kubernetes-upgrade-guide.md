# Kubernetes バージョンアップグレード手順書

このドキュメントでは、k8s_myHomeプロジェクトのKubernetesバージョンをアップグレードする手順を説明します。

## 現在のバージョン

- **Kubernetes**: v1.29.0
- **OS**: Ubuntu 24.04 LTS
- **コンテナランタイム**: containerd
- **CNI**: Flannel

## アップグレード前の準備

### 1. バージョン互換性の確認

アップグレード前に以下の互換性を確認してください：

- [Kubernetes バージョンスキューポリシー](https://kubernetes.io/docs/setup/release/version-skew-policy/)
  - 1マイナーバージョンずつアップグレード（例: 1.29 → 1.30 → 1.31）
- [kubeadm アップグレードガイド](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)
- CNI（Flannel）の互換性
- アプリケーションの互換性

### 2. 現在の環境のバックアップ

```bash
# 重要な設定のバックアップ
kubectl get all --all-namespaces -o yaml > backup-resources.yaml
kubectl get pv,pvc --all-namespaces -o yaml > backup-storage.yaml
kubectl get secrets --all-namespaces -o yaml > backup-secrets.yaml
```

## アップグレード手順

### 方法1: 完全再構築（推奨）

最もシンプルで確実な方法です。

#### 1. 設定ファイルの更新

```bash
# automation/infrastructure/main.tf を編集
# 以下の箇所を新しいバージョンに変更

# 例: v1.29.0 → v1.30.0 へのアップグレード
# 変更前:
# "echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list",
# "sudo apt install -y kubelet=1.29.0-1.1 kubeadm=1.29.0-1.1 kubectl=1.29.0-1.1",

# 変更後:
# "echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list",
# "sudo apt install -y kubelet=1.30.0-1.1 kubeadm=1.30.0-1.1 kubectl=1.30.0-1.1",
```

`automation/infrastructure/main.tf`の変更箇所：
- **Control Plane provisioner** (約250行目付近)
- **Worker Node provisioner** (約450行目付近)

#### 2. クラスターの再構築

```bash
# プロジェクトルートで実行
cd /home/ksera/k8s_myHome

# 完全再構築
make all
```

#### 3. 動作確認

```bash
# バージョン確認
kubectl version --short

# ノード状態確認
kubectl get nodes

# Pod状態確認
kubectl get pods --all-namespaces
```

### 方法2: インプレースアップグレード（上級者向け）

既存のクラスターを維持したままアップグレードする方法です。

#### 1. Control Planeのアップグレード

```bash
# Control Planeノードで実行
ssh k8suser@192.168.122.10

# kubeadmのアップグレード
sudo apt update
sudo apt-mark unhold kubeadm
sudo apt install -y kubeadm=1.30.0-1.1
sudo apt-mark hold kubeadm

# アップグレードプランの確認
sudo kubeadm upgrade plan

# Control Planeのアップグレード
sudo kubeadm upgrade apply v1.30.0

# kubelet/kubectlのアップグレード
sudo apt-mark unhold kubelet kubectl
sudo apt install -y kubelet=1.30.0-1.1 kubectl=1.30.0-1.1
sudo apt-mark hold kubelet kubectl

# kubeletの再起動
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

#### 2. Worker Nodeのアップグレード

各Worker Nodeで順番に実行：

```bash
# Worker Nodeをドレイン
kubectl drain k8s-worker1 --ignore-daemonsets

# Worker Nodeで実行
ssh k8suser@192.168.122.11

# kubeadm/kubelet/kubectlのアップグレード
sudo apt update
sudo apt-mark unhold kubeadm kubelet kubectl
sudo apt install -y kubeadm=1.30.0-1.1 kubelet=1.30.0-1.1 kubectl=1.30.0-1.1
sudo apt-mark hold kubeadm kubelet kubectl

# ノード設定のアップグレード
sudo kubeadm upgrade node

# kubeletの再起動
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Control Planeから実行
kubectl uncordon k8s-worker1
```

Worker2でも同様の手順を実行。

## アップグレード後の確認

### 1. クラスター状態の確認

```bash
# バージョン確認
kubectl version --short

# ノード状態
kubectl get nodes

# システムPod
kubectl get pods -n kube-system

# アプリケーション
kubectl get applications -n argocd
```

### 2. アプリケーション互換性の確認

```bash
# ArgoCD同期状態
kubectl get applications -n argocd -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status"

# Harbor動作確認
kubectl get pods -n harbor

# 各種CronJob確認
kubectl get cronjobs --all-namespaces
```

## トラブルシューティング

### よくある問題と対処法

#### 1. Podが起動しない

```bash
# イメージの互換性確認
kubectl describe pod <pod-name> -n <namespace>

# 必要に応じてイメージ更新
kubectl set image deployment/<deployment-name> <container-name>=<new-image> -n <namespace>
```

#### 2. APIバージョンの非互換

```bash
# 非推奨APIの確認
kubectl api-versions | grep -E "v1beta|v1alpha"

# マニフェストの更新が必要な場合
# manifests/ 配下のファイルを新しいAPIバージョンに更新
```

#### 3. CNIの問題

```bash
# Flannelの再インストール
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```

## 注意事項

1. **本番環境での実施前に必ずテスト環境で検証**
2. **アップグレードは1つのマイナーバージョンずつ実施**
3. **etcdのバックアップを必ず取得**
4. **アップグレード中のサービス停止を考慮**

## 更新履歴

- 2025-01-19: 初版作成（v1.29.0対応）

## 関連ドキュメント

- [公式Kubernetesアップグレードガイド](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)
- [kubeadmアップグレードガイド](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)
- [バージョンスキューポリシー](https://kubernetes.io/docs/setup/release/version-skew-policy/)