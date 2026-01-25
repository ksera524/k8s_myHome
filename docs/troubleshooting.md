# トラブルシューティングガイド

## 概要

k8s_myHomeで発生する可能性のある問題と、その解決方法について説明します。

## このガイドの範囲

- 対象: 障害時の一次切り分け、ログ/イベント確認、代表的な復旧手順
- 非対象: 日常運用は `docs/operations-guide.md`、初期構築は `docs/setup-guide.md`、バージョンアップは `docs/kubernetes-upgrade-guide.md`

## 一般的な診断コマンド

```bash
# 確認フェーズ
make phase5

# 詳細な状態確認
kubectl get nodes -o wide
kubectl get applications -n argocd
kubectl get pods -A | grep -v Running | head -20

# ログ確認
cat automation/run.log
```

## セットアップ時の問題

### 1. make all が失敗する

#### 症状
```
ERROR: make all failed
```

#### 原因と解決方法

**権限不足**
```bash
# sudo権限確認
sudo -v

# libvirtグループ確認
groups | grep libvirt

# グループに追加（必要な場合）
sudo usermod -aG libvirt $USER
# ログアウト・ログイン必要
```

**ディスク容量不足**
```bash
# 容量確認
df -h

# 必要容量: 200GB以上
# 不要なファイル削除
sudo apt clean
docker system prune -a
```

**ネットワーク問題**
```bash
# DNS確認
nslookup google.com

# プロキシ設定（必要な場合）
export HTTP_PROXY=http://proxy.example.com:8080
export HTTPS_PROXY=http://proxy.example.com:8080
```

#### ログ確認
```bash
cat automation/run.log
```

### 2. VM が起動しない

#### 症状
```
Failed to start domain k8s-control-plane
```

#### 解決方法

```bash
# libvirtサービス確認
sudo systemctl status libvirtd
sudo systemctl restart libvirtd

# ネットワーク確認
sudo virsh net-list --all
sudo virsh net-start default

# VM強制削除と再作成
cd automation/infrastructure
terraform destroy -auto-approve
terraform apply -auto-approve
```

### 3. Terraform エラー

#### 症状
```
Error: Error acquiring the state lock
```

#### 解決方法

```bash
# ロック解除
cd automation/infrastructure
rm -f .terraform.lock.hcl
terraform force-unlock <lock-id>

# 状態ファイルリセット
rm -f terraform.tfstate*
terraform init
```

## Kubernetes クラスター問題

### 1. ノードが NotReady

#### 症状
```
NAME                STATUS     ROLES
k8s-control-plane   NotReady   control-plane
```

#### 診断と解決

```bash
# ノード詳細確認
kubectl describe node k8s-control-plane

# kubelet状態確認
ssh k8suser@192.168.122.10
sudo systemctl status kubelet
sudo journalctl -u kubelet -n 100

# 一般的な修正
sudo systemctl restart kubelet
sudo systemctl restart containerd
```

### 2. Pod が Pending/CrashLoopBackOff

#### Pending状態

```bash
# Pod詳細確認
kubectl describe pod <pod-name> -n <namespace>

# よくある原因：
# 1. リソース不足
kubectl top nodes
kubectl describe node | grep -A 5 "Allocated resources"

# 2. PVC未作成
kubectl get pvc -n <namespace>

# 3. イメージプル失敗
kubectl get events -n <namespace>
```

#### CrashLoopBackOff

```bash
# ログ確認
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous

# 起動コマンド確認
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 10 command

# 一時的なデバッグPod起動
kubectl run -it debug --image=<same-image> --restart=Never -- /bin/sh
```

### 3. Service に接続できない

#### 症状
```
curl: (7) Failed to connect to service
```

#### 診断

```bash
# Service確認
kubectl get svc -n <namespace>
kubectl get endpoints -n <namespace>

# Pod selector確認
kubectl get svc <service-name> -n <namespace> -o yaml | grep selector -A 5
kubectl get pods -n <namespace> --show-labels

# DNS確認
kubectl run -it --rm debug --image=alpine --restart=Never -- nslookup <service>.<namespace>
```

## ArgoCD 問題

### 1. Application が OutOfSync

#### 症状
```
SYNC STATUS: OutOfSync
```

#### 解決方法

```bash
# 差分確認
kubectl get application <app-name> -n argocd -o jsonpath='{.status}'

# 手動同期
kubectl patch application <app-name> -n argocd \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# 強制同期
argocd app sync <app-name> --force --prune
```

### 2. ArgoCD UIにアクセスできない

```bash
# Port Forward再起動
pkill -f "port-forward.*argocd"
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Service確認
kubectl get svc -n argocd
kubectl logs -n argocd deployment/argocd-server
```

## Harbor 問題

### 1. イメージプッシュ失敗

#### 症状
```
unauthorized: unauthorized to access repository
```

#### 解決方法

```bash
# ログイン（内部）
docker login harbor.internal.qroksera.com
# Username: admin
# Password: <harbor-admin-password>（初期値は変更）

# hosts ファイル確認
grep harbor.internal.qroksera.com /etc/hosts
# なければ追加
echo "192.168.122.100 harbor.internal.qroksera.com" | sudo tee -a /etc/hosts

# 内部CAを端末に信頼させる
# (k8s-myhome-internal-ca を OS の信頼ストアへ追加)

# GitHub Actions Runner で TLS エラーが出る場合
# add-runner.sh で Runner(dind) に内部CAを配布するため、再作成する
# make add-runner REPO=your-repo

# レジストリSecret再作成
kubectl delete secret harbor-registry-secret -n <namespace>
kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=harbor.internal.qroksera.com \
  --docker-username=admin \
  --docker-password=<harbor-admin-password> \
  -n <namespace>
```

### 2. Harbor UIアクセス不可

```bash
# Pod状態確認
kubectl get pods -n harbor

# Core コンポーネント再起動
kubectl rollout restart deployment/harbor-core -n harbor

# データベース確認
kubectl logs -n harbor statefulset/harbor-database
```

## External Secrets 問題

### 1. Secret が作成されない

#### 症状
```
ExternalSecret status: SecretSyncedError
```

#### 診断と解決

```bash
# ClusterSecretStore状態
kubectl describe clustersecretstore pulumi-esc-store

# ExternalSecret詳細
kubectl describe externalsecret <name> -n <namespace>

# Pulumi token確認
kubectl get secret pulumi-access-token -n external-secrets -o yaml

# 手動同期トリガー
kubectl annotate externalsecret <name> -n <namespace> \
  force-sync="$(date +%s)" --overwrite
```

## GitHub Actions Runner 問題

### 1. Runner が起動しない

```bash
# Runner Pod確認
kubectl get pods -n arc-systems

# Runner ScaleSet確認
helm list -n arc-systems
helm get values <runner-name> -n arc-systems

# Controller ログ
kubectl logs -n arc-systems deployment/arc-gha-runner-scale-set-controller

# ServiceAccount確認
kubectl get serviceaccount github-actions-runner -n arc-systems
```

### 2. ジョブが Queued のまま

```bash
# Runner設定確認
helm get values <runner-name> -n arc-systems | grep -E "minRunners|maxRunners"

# minRunners を1以上に設定
helm upgrade <runner-name> \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --namespace arc-systems \
  --set minRunners=1 \
  --wait
```

## ネットワーク問題

### 1. LoadBalancer IP が割り当てられない

```bash
# MetalLB確認
kubectl get pods -n metallb-system
kubectl logs -n metallb-system deployment/controller

# IPプール確認
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system

# Service再作成
kubectl delete svc <service-name> -n <namespace>
kubectl apply -f service.yaml
```

### 2. Ingress が機能しない

```bash
# NGINX Ingress Controller確認
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# Ingress確認
kubectl get ingress -A
kubectl describe ingress <name> -n <namespace>

# 証明書確認
kubectl get certificate -A
kubectl describe certificate <name> -n <namespace>
```

## ストレージ問題

### 1. PVC が Pending

```bash
# StorageClass確認
kubectl get storageclass
kubectl describe storageclass local-path

# PVC詳細
kubectl describe pvc <name> -n <namespace>

# Provisioner Pod確認
kubectl get pods -n local-path-storage
kubectl logs -n local-path-storage deployment/local-path-provisioner
```

### 2. ディスク容量不足

```bash
# ノードの容量確認
ssh k8suser@192.168.122.10 'df -h'
ssh k8suser@192.168.122.11 'df -h'
ssh k8suser@192.168.122.12 'df -h'

# 不要なイメージ削除
ssh k8suser@192.168.122.10 'sudo crictl rmi --prune'

# 古いログ削除
ssh k8suser@192.168.122.10 'sudo journalctl --vacuum-time=7d'
```

## パフォーマンス問題

### 1. クラスター全体が遅い

```bash
# リソース使用状況
kubectl top nodes
kubectl top pods -A --sort-by=cpu
kubectl top pods -A --sort-by=memory

# メトリクスサーバー確認
kubectl get deployment metrics-server -n kube-system

# etcd パフォーマンス
ssh k8suser@192.168.122.10
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health
```

### 2. 特定のPodが遅い

```bash
# Pod リソース確認
kubectl describe pod <pod-name> -n <namespace> | grep -A 10 resources

# リミット調整
kubectl set resources deployment <name> -n <namespace> \
  --limits=cpu=1000m,memory=1Gi \
  --requests=cpu=100m,memory=128Mi
```

## 完全リセット手順

すべての問題解決策が失敗した場合：

```bash
# 1. VM削除確認
sudo virsh list --all
sudo virsh destroy <vm-name>
sudo virsh undefine <vm-name>

# 2. ネットワーククリーンアップ
sudo virsh net-destroy default
sudo virsh net-start default

# 3. Terraformステートクリーン
cd automation/infrastructure
rm -rf .terraform terraform.tfstate*

# 4. 再構築
cd ~/k8s_myHome
make all
```

## ログ収集スクリプト

問題報告用のログ収集：

```bash
#!/bin/bash
# collect-logs.sh

LOG_DIR="k8s-debug-$(date +%Y%m%d-%H%M%S)"
mkdir -p $LOG_DIR

# システム情報
make phase5 > $LOG_DIR/verify.txt 2>&1

# ノード情報
kubectl get nodes -o wide > $LOG_DIR/nodes.txt
kubectl describe nodes > $LOG_DIR/nodes-describe.txt

# Pod情報
kubectl get pods -A > $LOG_DIR/pods.txt
kubectl get pods -A | grep -v Running > $LOG_DIR/problem-pods.txt

# イベント
kubectl get events -A > $LOG_DIR/events.txt

# ArgoCD
kubectl get applications -n argocd > $LOG_DIR/argocd-apps.txt

# ログ
cp automation/run.log $LOG_DIR/ 2>/dev/null

# アーカイブ作成
tar czf $LOG_DIR.tar.gz $LOG_DIR/
echo "ログ収集完了: $LOG_DIR.tar.gz"
```

## サポート

解決しない場合は、収集したログと共に[GitHub Issues](https://github.com/ksera524/k8s_myHome/issues)で報告してください。
