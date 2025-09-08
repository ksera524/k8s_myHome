# 🚀 k8s_myHome クイックスタートガイド

このガイドでは、k8s_myHomeプロジェクトを最速でデプロイする手順を説明します。

## 📋 前提条件

### ハードウェア要件
- **CPU**: 8コア以上（推奨: 12コア）
- **メモリ**: 24GB以上（推奨: 32GB）
- **ストレージ**: 200GB以上のSSD
- **ネットワーク**: インターネット接続

### ソフトウェア要件
- **OS**: Ubuntu 24.04 LTS（クリーンインストール推奨）
- **ユーザー**: sudo権限を持つ非rootユーザー

## 🎯 15分でデプロイ完了

### ステップ1: リポジトリ取得
```bash
# プロジェクトクローン
git clone https://github.com/ksera524/k8s_myHome.git
cd k8s_myHome
```

### ステップ2: 設定ファイル準備

```bash
# テンプレートからコピー
cp automation/settings.toml.example automation/settings.toml

# 設定編集
vim automation/settings.toml
```

**必須設定項目**:
```toml
[GitHub]
username = "your-github-username"
pat = "ghp_xxxxxxxxxxxxxxxxxxxxx"  # GitHub Personal Access Token

[Pulumi]
access_token = "pul-xxxxxxxxxxxxx"  # Pulumi Access Token

[GitHub.OAuth]
client_id = "Ov23lixxxxxxxxxx"      # GitHub OAuth App Client ID
client_secret = "xxxxxxxxxxxxxxxx"   # GitHub OAuth App Client Secret

[GitHub.ARC]
arc_repositories = [
    ["your-repo", 1, 3, "Your repository"],
]
```

### ステップ3: 自動デプロイ実行

```bash
# 完全自動デプロイ（約10-15分）
make all
```

実行内容:
1. ホスト環境セットアップ
2. 仮想マシン作成
3. Kubernetesクラスター構築
4. プラットフォームサービスデプロイ
5. GitOps設定

### ステップ4: デプロイ確認

```bash
# ステータス確認
make status

# 期待される出力:
# ✅ Host Setup: 完了
# ✅ VMs: 3台稼働中
# ✅ Kubernetes: Ready (3 nodes)
# ✅ ArgoCD: Healthy
# ✅ Harbor: Running
# ✅ LoadBalancer: 192.168.122.100
```

## 🔑 アクセス情報

### ArgoCD（GitOps管理）
```bash
# ポートフォワード
kubectl port-forward svc/argocd-server -n argocd 8080:443

# ブラウザでアクセス
# URL: https://localhost:8080
# Username: admin
# Password: 以下のコマンドで取得
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### Harbor（コンテナレジストリ）
```bash
# 直接アクセス
# URL: http://192.168.122.100
# Username: admin
# Password: te3CFrgdMaBJTCg4UWJv
```

### Kubernetes Dashboard（オプション）
```bash
# インストール
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# アクセストークン作成
kubectl create serviceaccount dashboard-admin -n kubernetes-dashboard
kubectl create clusterrolebinding dashboard-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=kubernetes-dashboard:dashboard-admin

# トークン取得
kubectl -n kubernetes-dashboard create token dashboard-admin
```

## 🎮 基本操作

### アプリケーションデプロイ
```bash
# ArgoCD経由でアプリケーション追加
kubectl apply -f manifests/apps/your-app/application.yaml

# または直接デプロイ
kubectl apply -f manifests/apps/your-app/manifest.yaml
```

### GitHub Actionsランナー追加
```bash
# 特定リポジトリ用のランナー追加
make add-runner REPO=your-repository-name

# 確認
kubectl get pods -n arc-systems
```

### 環境クリーンアップ
```bash
# Terraform経由でインフラストラクチャ削除
cd automation/infrastructure
terraform destroy -auto-approve
```

## 🔧 トラブルシューティング

### よくある問題と解決策

#### 1. VMが起動しない
```bash
# libvirtサービス確認
sudo systemctl status libvirtd

# ネットワーク確認
sudo virsh net-list --all

# 手動起動
sudo virsh net-start default
```

#### 2. Kubernetesノードが Not Ready
```bash
# ノード確認
kubectl get nodes -o wide

# ログ確認
ssh k8suser@192.168.122.10
journalctl -u kubelet -f
```

#### 3. ArgoCD同期エラー
```bash
# アプリケーション状態確認
kubectl get applications -n argocd

# 手動同期
kubectl patch application <app-name> -n argocd \
  --type merge -p '{"operation":{"sync":{"syncStrategy":{"hook":{}}}}}'
```

#### 4. Harbor証明書エラー
```bash
# 証明書再生成
kubectl delete secret harbor-tls -n harbor
kubectl apply -f manifests/resources/infrastructure/cert-manager/harbor-certificate.yaml

# Pod再起動
kubectl rollout restart deployment -n harbor
```

## 📊 リソース使用状況確認

```bash
# クラスター全体
kubectl top nodes
kubectl top pods --all-namespaces

# VM個別確認
sudo virsh dominfo k8s-control-plane-1
sudo virsh dominfo k8s-worker-1
sudo virsh dominfo k8s-worker-2

# ストレージ確認
df -h /var/lib/libvirt/images
kubectl get pv
```

## 🚀 次のステップ

1. **アプリケーションデプロイ**
   - [アプリケーション追加ガイド](development/setup.md)
   - [GitOps ワークフロー](operations/deployment-guide.md)

2. **モニタリング設定**
   - Prometheus + Grafana導入
   - アラート設定

3. **バックアップ設定**
   - [バックアップ・リストアガイド](operations/backup-restore.md)

4. **セキュリティ強化**
   - Network Policy設定
   - RBAC詳細設定

## 💡 Tips & Tricks

### エイリアス設定
```bash
# ~/.bashrcに追加
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kga='kubectl get all'
alias kaf='kubectl apply -f'
alias kdel='kubectl delete'
alias klog='kubectl logs'
```

### kubectl設定
```bash
# 自動補完有効化
source <(kubectl completion bash)
echo "source <(kubectl completion bash)" >> ~/.bashrc

# デフォルトnamespace設定
kubectl config set-context --current --namespace=default
```

### SSHショートカット
```bash
# ~/.ssh/configに追加
Host k8s-cp
    HostName 192.168.122.10
    User k8suser
    
Host k8s-w1
    HostName 192.168.122.11
    User k8suser
    
Host k8s-w2
    HostName 192.168.122.12
    User k8suser
```

## 📚 関連ドキュメント

- [詳細アーキテクチャ](architecture/README.md)
- [運用マニュアル](operations/deployment-guide.md)
- [トラブルシューティング詳細](operations/troubleshooting.md)
- [開発者ガイド](development/setup.md)

## 🆘 サポート

問題が解決しない場合:
1. [GitHub Issues](https://github.com/ksera524/k8s_myHome/issues)で報告
2. [Discussions](https://github.com/ksera524/k8s_myHome/discussions)で質問
3. ログを添付（`make logs > debug.log`）

---
*最終更新: 2025-01-09*