# よくある問題と解決方法

## ネットワーク関連

### 問題: VMがインターネットに接続できない
**症状**: 
- `ping 8.8.8.8` が失敗
- パッケージのインストールができない

**解決方法**:
```bash
# ホストのネットワーク設定確認
sudo virsh net-list --all
sudo virsh net-info k8s-network

# ネットワークを再起動
sudo virsh net-destroy k8s-network
sudo virsh net-start k8s-network

# iptables/nftablesの確認
sudo iptables -t nat -L POSTROUTING -n -v
```

### 問題: MetalLBがIPを割り当てない
**症状**:
- Service が `<pending>` 状態のまま

**解決方法**:
```bash
# MetalLB Podの状態確認
kubectl -n metallb-system get pods

# IPAddressPoolの確認
kubectl -n metallb-system get ipaddresspool -o yaml

# L2Advertisementの確認
kubectl -n metallb-system get l2advertisement -o yaml
```

## Kubernetes関連

### 問題: ノードがNotReady状態
**症状**:
- `kubectl get nodes` でNotReady

**解決方法**:
```bash
# 該当ノードにSSH
ssh k8suser@<node-ip>

# kubeletログ確認
sudo journalctl -u kubelet -f

# CNI（Flannel）の状態確認
kubectl -n kube-flannel get pods

# ノードの詳細確認
kubectl describe node <node-name>
```

### 問題: Podが起動しない
**症状**:
- Pod が `Pending` または `CrashLoopBackOff`

**解決方法**:
```bash
# Podの詳細確認
kubectl describe pod <pod-name> -n <namespace>

# ログ確認
kubectl logs <pod-name> -n <namespace>

# リソース不足の確認
kubectl top nodes
kubectl describe nodes | grep -A5 "Allocated resources"
```

## Harbor関連

### 問題: Harborの証明書エラー
**症状**:
- `x509: certificate signed by unknown authority`

**解決方法**:
```bash
# CA証明書の再配布
cd automation/platform
./harbor-cert-fix.sh

# 各ノードでCA証明書を確認
kubectl get pods -o wide | grep harbor-ca-trust

# Dockerデーモンの再起動
sudo systemctl restart docker
# またはcontainerdの場合
sudo systemctl restart containerd
```

### 問題: Harborへのpushが失敗
**症状**:
- `unauthorized: unauthorized to access repository`

**解決方法**:
```bash
# Harbor認証情報の確認
kubectl get secret harbor-auth -n arc-systems -o yaml

# Docker/Podmanログイン
docker login 192.168.122.100 -u admin -p Harbor12345

# イメージのタグ付け確認
docker tag myimage:latest 192.168.122.100/library/myimage:latest
```

## ArgoCD関連

### 問題: ArgoCDがリポジトリに接続できない
**症状**:
- `ComparisonError` または `Unknown`

**解決方法**:
```bash
# リポジトリ設定確認
argocd repo list

# 手動でリポジトリ追加
argocd repo add https://github.com/user/repo \
  --username <username> \
  --password <token>

# Application再同期
argocd app sync <app-name> --force
```

## External Secrets関連

### 問題: Secretが作成されない
**症状**:
- ExternalSecretが `SecretSyncError`

**解決方法**:
```bash
# ClusterSecretStore状態確認
kubectl get clustersecretstore -o yaml

# ExternalSecret状態確認
kubectl describe externalsecret <name> -n <namespace>

# Pulumi ESC接続確認
kubectl logs -n external-secrets deployment/external-secrets
```

## パフォーマンス関連

### 問題: クラスターの動作が遅い
**解決方法**:
```bash
# リソース使用状況確認
kubectl top nodes
kubectl top pods --all-namespaces

# ディスクI/O確認（各ノードで）
iostat -x 1

# スワップ使用確認
free -h

# etcdパフォーマンス確認
kubectl -n kube-system exec etcd-k8s-control-plane-1 -- \
  etcdctl endpoint status --write-out=table
```

## 一般的なデバッグコマンド

```bash
# 全体的な状態確認
kubectl get all --all-namespaces

# イベント確認
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# ノードのシステムログ
ssh k8suser@<node-ip> 'sudo journalctl -xe'

# CoreDNS動作確認
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup kubernetes.default
```