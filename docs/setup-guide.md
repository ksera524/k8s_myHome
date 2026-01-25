# セットアップガイド

## 前提条件

### ハードウェア要件

#### 最小要件
- **CPU**: 8コア以上
- **メモリ**: 16GB以上
- **ストレージ**: 200GB以上の空き容量
- **ネットワーク**: インターネット接続

#### 推奨要件
- **CPU**: 12コア以上
- **メモリ**: 32GB以上
- **ストレージ**: SSD 500GB以上
- **ネットワーク**: 有線接続推奨

### ソフトウェア要件

- **OS**: Ubuntu 24.04 LTS（ホストマシン）
- **Git**: バージョン管理
- **Make**: 自動化ツール
- **sudo権限**: インストール作業に必要

## セットアップ手順

### 1. リポジトリのクローン

```bash
# リポジトリをクローン
git clone https://github.com/ksera524/k8s_myHome.git
cd k8s_myHome
```

### 2. 設定ファイルの準備

#### 2.1 設定ファイルのコピー

```bash
cp automation/settings.toml.example automation/settings.toml
```

#### 2.2 必須設定項目の編集

```bash
vim automation/settings.toml
```

以下の項目を必ず設定してください：

```toml
# Pulumi設定（External Secrets Operator用）
[pulumi]
access_token = "pul-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"  # Pulumi Access Token
organization = "your-org"  # Pulumi組織名
project = "k8s"
environment = "secret"

# GitHub設定（GitHub Actions Runner用）
[github]
username = "your-github-username"  # GitHubユーザー名

# GitHub Actions Runner対象リポジトリ
arc_repositories = [
    ["your-repo", 1, 3, "Your repository description"],
]

# USB外部ストレージ（使用する場合）
[host_setup]
usb_device_name = "sdb"  # lsblkで確認したデバイス名
```

### 3. 完全自動セットアップ

最も簡単な方法は`make all`コマンドです：

```bash
make all
```

このコマンドは以下の処理を自動実行します：
1. ホストマシンのセットアップ
2. VM作成とKubernetesクラスター構築
3. GitOps準備（ArgoCD/ESOなど）
4. GitOpsによるアプリケーション展開
5. 確認

### 4. ステップバイステップセットアップ（手動）

自動セットアップの代わりに、各ステップを個別に実行することも可能です。

#### 4.1 ホストセットアップ

```bash
# ホストマシンの準備
make phase1
```

このステップでは以下を実行：
- 必要なパッケージのインストール
- libvirt/QEMU/KVM設定
- ストレージ設定
- ネットワーク設定

**注意**: グループメンバーシップ更新のため、一度ログアウト・ログインが必要な場合があります。

#### 4.2 インフラストラクチャ構築

```bash
# VM作成とKubernetesクラスター構築
make phase2
```

このステップでは以下を実行：
- 3台のVMを作成（Terraform使用）
- Kubernetesクラスターの初期化（kubeadm）
- ワーカーノードのジョイン
- 基本的なネットワーク設定

進捗確認：
```bash
# VMの状態確認
sudo virsh list --all

# Kubernetesノード確認
ssh k8suser@192.168.122.10 'kubectl get nodes'
```

#### 4.3 プラットフォームサービス

```bash
# GitOps準備（ArgoCD/ESOなど）
make phase3
```

このステップでは以下を実行：
- MetalLB（LoadBalancer）
- NGINX Gateway Fabric（Gateway API）
- cert-manager（証明書管理）
- ArgoCD（GitOps）
- Harbor（コンテナレジストリ）
- External Secrets Operator

進捗確認：
```bash
# サービス状態確認
kubectl get pods --all-namespaces
```

#### 4.4 GitOpsアプリケーション展開

```bash
make phase4
```

#### 4.5 確認

```bash
make phase5
```

### 5. 初期アクセス情報

#### ArgoCD

```bash
# Port Forwardの設定
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 別ターミナルでアクセス
# URL: https://localhost:8080
# Username: admin
# Password: 以下のコマンドで取得
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

#### Harbor

```bash
# Port Forwardの設定
kubectl port-forward svc/harbor-core -n harbor 8081:80

# 別ターミナルでアクセス
# URL: http://localhost:8081
# Username: admin
# Password: <harbor-admin-password>（初期値は変更）
```

#### Kubernetes Dashboard（オプション）

```bash
# Control PlaneへSSH
ssh k8suser@192.168.122.10

# kubeconfigの確認
kubectl config view
```

### 6. アプリケーションのデプロイ

GitOpsによる自動デプロイが設定されています。アプリケーションは`manifests/apps/`に配置されており、ArgoCDが自動的に同期します。

#### 手動同期（必要な場合）

```bash
# ArgoCD CLIを使用
argocd app sync user-applications --grpc-web --insecure \
  --server localhost:8080

# または kubectl を使用
kubectl patch application user-applications -n argocd \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

### 7. GitHub Actions Runner設定

#### 自動設定（推奨）

settings.tomlに`arc_repositories`を設定済みの場合、`make add-runners-all`で一括作成できます。

#### 手動追加

```bash
# 個別リポジトリ用Runner追加
make add-runner REPO=your-repository-name

# 一括追加（settings.tomlから）
make add-runners-all
```

### 8. セットアップ検証

```bash
# 確認フェーズ
make phase5

# ログ確認
cat automation/run.log
```

## トラブルシューティング

### よくある問題と解決方法

#### 1. VMが起動しない

```bash
# libvirtサービスの確認
sudo systemctl status libvirtd

# ネットワークの確認
sudo virsh net-list --all

# 権限の確認
groups | grep libvirt
```

#### 2. Kubernetesノードが Ready にならない

```bash
# ノードの詳細確認
kubectl describe node <node-name>

# kubeletログ確認
ssh k8suser@192.168.122.10 'journalctl -u kubelet -f'
```

#### 3. ArgoCD同期エラー

```bash
# Application状態確認
kubectl get applications -n argocd

# 同期エラーの詳細
kubectl describe application <app-name> -n argocd
```

#### 4. External Secrets エラー

```bash
# ClusterSecretStore確認
kubectl get clustersecretstore

# SecretStore状態
kubectl describe clustersecretstore pulumi-esc-store
```

### クリーンアップ

問題が解決しない場合、再構築します：

```bash
# 再実行
make all
```

## 次のステップ

セットアップが完了したら、以下のドキュメントを参照してください：

- [運用ガイド](operations-guide.md) - 日常的な運用タスク
- [アプリケーション管理](applications.md) - アプリケーションのデプロイと管理
- [トラブルシューティング](troubleshooting.md) - 詳細な問題解決ガイド

## サポート

問題が発生した場合は、以下のリソースを利用してください：

- [GitHub Issues](https://github.com/ksera524/k8s_myHome/issues)
- [プロジェクトWiki](https://github.com/ksera524/k8s_myHome/wiki)
- ログファイル: `/home/ksera/k8s_myHome/automation/run.log`
