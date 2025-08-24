# デプロイメントガイド

## 目次
1. [前提条件](#前提条件)
2. [完全デプロイメント](#完全デプロイメント)
3. [個別デプロイメント](#個別デプロイメント)
4. [検証手順](#検証手順)
5. [トラブルシューティング](#トラブルシューティング)

## 前提条件

### ハードウェア要件
- CPU: 8コア以上
- メモリ: 24GB以上
- ストレージ: 200GB以上の外部USB/SSD

### ソフトウェア要件
- Ubuntu 24.04 LTS
- インターネット接続
- sudo権限

## 完全デプロイメント

### 1. 設定ファイルの準備
```bash
# 環境変数ファイルを作成
cp config/secrets/.env.example config/secrets/.env
# .envファイルを編集して必要な値を設定
```

### 2. 自動デプロイメント実行
```bash
# 完全な環境構築（推奨）
make all

# 特定のリポジトリにGitHub Actions Runnerを追加
make add-runner REPO=your-repository-name
```

## 個別デプロイメント

### Host Setup（ホスト準備）
```bash
cd automation/host-setup
./setup-host.sh
# ログアウト・ログインが必要
./setup-storage.sh
./verify-setup.sh
```

### Infrastructure（VM + Kubernetes）
```bash
cd automation/infrastructure
./clean-and-deploy.sh
```

### Platform（プラットフォームサービス）
```bash
cd automation/platform
./platform-deploy.sh
```

## 検証手順

### 1. クラスター状態確認
```bash
# ノード状態
kubectl get nodes

# 全Podの状態
kubectl get pods --all-namespaces

# サービス状態
kubectl get svc --all-namespaces
```

### 2. プラットフォームサービス確認

#### ArgoCD
```bash
# ポートフォワード
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 初期パスワード取得
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

#### Harbor
```bash
# ポートフォワード
kubectl port-forward svc/harbor-core -n harbor 8081:80

# デフォルト認証情報
# Username: admin
# Password: Harbor12345
```

### 3. LoadBalancer IP確認
```bash
# NGINX Ingress Controller
kubectl -n ingress-nginx get service ingress-nginx-controller

# MetalLB IP Pool状態
kubectl -n metallb-system get ipaddresspool
```

## トラブルシューティング

### VM作成失敗
```bash
# VMリスト確認
sudo virsh list --all

# VM削除して再作成
cd automation/infrastructure
./clean-and-deploy.sh
```

### Kubernetes API接続エラー
```bash
# kubeconfigの確認
ls -la ~/.kube/config

# コントロールプレーンへのSSH
ssh k8suser@192.168.122.10
sudo systemctl status kubelet
```

### ArgoCD同期エラー
```bash
# Application状態確認
kubectl get applications -n argocd

# 手動同期
argocd app sync <app-name>
```

詳細なトラブルシューティングは[トラブルシューティングガイド](../troubleshooting/common-issues.md)を参照してください。