# 📘 デプロイメントガイド

## 概要

このガイドでは、k8s_myHomeの詳細なデプロイメント手順と、各フェーズでの確認事項を説明します。

## 前提条件チェックリスト

### ハードウェア要件
- [ ] CPU: 8コア以上
- [ ] メモリ: 24GB以上  
- [ ] ストレージ: 200GB以上のSSD
- [ ] ネットワーク: 安定したインターネット接続

### ソフトウェア要件
- [ ] Ubuntu 24.04 LTS（クリーンインストール）
- [ ] sudoers権限を持つ非rootユーザー
- [ ] SSHアクセス設定済み

### 外部サービス
- [ ] GitHubアカウント
- [ ] GitHub Personal Access Token (PAT)
- [ ] GitHub OAuth App（ArgoCD用）
- [ ] Pulumi Account（無料版可）

## フェーズ1: ホストセットアップ

### 1.1 基本環境準備

```bash
# システム更新
sudo apt update && sudo apt upgrade -y

# 必要なパッケージインストール
cd automation/host-setup
./setup-host.sh
```

**確認項目:**
```bash
# インストール確認
which qemu-system-x86_64
which virsh
which terraform
systemctl status libvirtd
```

### 1.2 libvirt権限設定

```bash
# libvirtグループへの追加
./setup-libvirt-sudo.sh

# 重要: 再ログイン必要
exit
ssh user@host
```

**確認項目:**
```bash
# グループ確認
groups | grep libvirt
# sudo無しでvirsh実行可能か
virsh list --all
```

### 1.3 ストレージプール設定

```bash
# ストレージプール作成
./setup-storage.sh
```

**確認項目:**
```bash
# プール確認
virsh pool-list --all
virsh pool-info default
# 容量確認
df -h /var/lib/libvirt/images
```

### 1.4 セットアップ検証

```bash
./verify-setup.sh
```

期待される出力:
```
✅ KVM/QEMU: インストール済み
✅ libvirt: 稼働中
✅ ネットワーク: default (active)
✅ ストレージプール: default (active)
✅ Terraform: v1.6.0
✅ 権限: OK
```

## フェーズ2: インフラストラクチャ構築

### 2.1 設定ファイル準備

```bash
cd ../..
cp automation/settings.toml.example automation/settings.toml
vim automation/settings.toml
```

**必須設定:**
```toml
[GitHub]
username = "your-username"
pat = "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

[GitHub.OAuth]
client_id = "Ov23liXXXXXXXXXXXXXX"
client_secret = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

[Pulumi]
access_token = "pul-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

[GitHub.ARC]
arc_repositories = [
    ["your-repo", 1, 3, "Your repository description"],
]
```

### 2.2 VM・Kubernetesクラスター構築

```bash
cd automation/infrastructure
./clean-and-deploy.sh
```

**実行内容:**
1. 既存環境クリーンアップ
2. Terraformでの VM作成
3. Kubernetesクラスター構築
4. ネットワーク設定

**進捗確認:**
```bash
# VM状態確認
sudo virsh list --all

# 期待される出力:
# Id   Name                  State
# 1    k8s-control-plane-1   running
# 2    k8s-worker-1          running
# 3    k8s-worker-2          running
```

### 2.3 クラスター接続確認

```bash
# kubeconfig取得
scp k8suser@192.168.122.10:~/.kube/config ~/.kube/config

# ノード確認
kubectl get nodes

# 期待される出力:
# NAME                  STATUS   ROLES           AGE   VERSION
# k8s-control-plane-1   Ready    control-plane   5m    v1.29.0
# k8s-worker-1          Ready    <none>          4m    v1.29.0
# k8s-worker-2          Ready    <none>          4m    v1.29.0
```

## フェーズ3: プラットフォームサービス

### 3.1 プラットフォームデプロイ

```bash
cd ../platform
./platform-deploy.sh
```

**デプロイ順序:**
1. MetalLB（LoadBalancer）
2. NGINX Ingress Controller
3. cert-manager（証明書管理）
4. External Secrets Operator
5. ArgoCD（GitOps）
6. Harbor（レジストリ）
7. Actions Runner Controller

### 3.2 サービス確認

```bash
# MetalLB確認
kubectl get ipaddresspool -n metallb-system
kubectl get service -n ingress-nginx

# ArgoCD確認
kubectl get pods -n argocd
kubectl get applications -n argocd

# Harbor確認
kubectl get pods -n harbor
curl -I http://192.168.122.100
```

### 3.3 ArgoCD初期設定

```bash
# 管理者パスワード取得
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# ポートフォワード
kubectl port-forward svc/argocd-server -n argocd 8080:443

# ブラウザアクセス
# https://localhost:8080
# Username: admin
# Password: 上記で取得したパスワード
```

## フェーズ4: アプリケーションデプロイ

### 4.1 GitOps経由デプロイ

```bash
# App-of-Appsパターンでの一括デプロイ
kubectl apply -f manifests/00-bootstrap/app-of-apps.yaml

# 同期状態確認
kubectl get applications -n argocd
```

### 4.2 個別アプリケーションデプロイ

```bash
# 例: 新規アプリケーション追加
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/ksera524/k8s_myHome
    targetRevision: HEAD
    path: manifests/apps/my-app
  destination:
    server: https://kubernetes.default.svc
    namespace: sandbox
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

### 4.3 GitHub Actionsランナー追加

```bash
# リポジトリ用ランナー追加
make add-runner REPO=your-repository

# 確認
kubectl get pods -n arc-systems
kubectl get autoscalingrunnersets -n arc-systems
```

## 運用タスク

### 日常運用

#### ステータス確認
```bash
# 全体ステータス
make status

# Pod状態
kubectl get pods --all-namespaces

# リソース使用状況
kubectl top nodes
kubectl top pods --all-namespaces
```

#### ログ確認
```bash
# 特定Podのログ
kubectl logs -n <namespace> <pod-name>

# 過去のログ
kubectl logs -n <namespace> <pod-name> --previous

# ストリーミング
kubectl logs -n <namespace> <pod-name> -f
```

### アップデート作業

#### Kubernetesアップデート
```bash
# ※ 要計画・要バックアップ
# Control Plane
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply v1.29.x

# Worker Nodes
kubectl drain <node-name> --ignore-daemonsets
sudo kubeadm upgrade node
kubectl uncordon <node-name>
```

#### アプリケーションアップデート
```bash
# マニフェスト更新後
git add manifests/
git commit -m "Update application version"
git push

# ArgoCD自動同期または手動同期
kubectl patch application <app-name> -n argocd \
  --type merge -p '{"operation":{"sync":{}}}'
```

### スケーリング

#### ワーカーノード追加
```hcl
# terraform.tfvars編集
worker_count = 3  # 2から3に変更

# 適用
terraform apply
```

#### Pod スケーリング
```bash
# Deployment スケール
kubectl scale deployment <name> -n <namespace> --replicas=5

# HPA設定
kubectl autoscale deployment <name> -n <namespace> \
  --min=2 --max=10 --cpu-percent=80
```

## トラブルシューティング

### よくある問題

#### 1. VM起動失敗
```bash
# エラーログ確認
sudo journalctl -u libvirtd -n 100

# VM強制停止・起動
sudo virsh destroy k8s-control-plane-1
sudo virsh start k8s-control-plane-1
```

#### 2. Pod起動失敗
```bash
# イベント確認
kubectl describe pod <pod-name> -n <namespace>

# ノードリソース確認
kubectl describe node <node-name>
```

#### 3. ArgoCD同期エラー
```bash
# アプリケーション詳細確認
kubectl describe application <app-name> -n argocd

# 手動リフレッシュ
argocd app get <app-name> --refresh
```

### 緊急時対応

#### サービス復旧手順
1. 影響範囲特定
2. ログ収集
3. 一時対処（Pod再起動等）
4. 根本原因調査
5. 恒久対策実施

#### ロールバック手順
```bash
# Deployment ロールバック
kubectl rollout undo deployment/<name> -n <namespace>

# ArgoCD経由
argocd app rollback <app-name> <revision>
```

## ベストプラクティス

### デプロイメント前
- [ ] バックアップ実施
- [ ] 変更内容レビュー
- [ ] テスト環境での検証
- [ ] ロールバック手順確認

### デプロイメント中
- [ ] 段階的デプロイ（カナリア/Blue-Green）
- [ ] ヘルスチェック監視
- [ ] ログ監視
- [ ] メトリクス確認

### デプロイメント後
- [ ] 動作確認テスト
- [ ] パフォーマンス確認
- [ ] ドキュメント更新
- [ ] 振り返り実施

---
*最終更新: 2025-01-09*