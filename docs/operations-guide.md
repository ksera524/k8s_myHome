# 運用ガイド

## 概要

本ガイドでは、k8s_myHome Kubernetesクラスターの日常的な運用・保守作業について説明します。

## このガイドの範囲

- 対象: 日常運用、監視、バックアップ/リストア、定期メンテナンス
- 非対象: 初期構築は `docs/setup-guide.md`、障害切り分けは `docs/troubleshooting.md`、バージョンアップは `docs/kubernetes-upgrade-guide.md`

## 運用方針（長期改善の前提）

- 変更は原則 GitOps で実施し、手動作業は例外として記録する
- 重要リソース（Gateway/Harbor/ESO/ArgoCD）の状態を日常確認に含める
- 失敗時は `automation/run.log` と Phase5 出力を併用して切り分ける

## Phase5 検証項目（自動）

`make phase5` では次の項目を確認します。

- Control Plane 接続（kubectl での疎通）
- 主要Namespaceの存在（argocd/monitoring/harbor/external-secrets-system/nginx-gateway/metallb-system）
- ノード Ready 状態
- Pod 異常（Running/Completed 以外）
- ArgoCD アプリの Sync/Health
- External Secrets（ClusterSecretStore/ExternalSecret）
- Gateway/LoadBalancer の基本状態

CIで実行する場合は `CI=true` を設定して SSH 検証をスキップします。
手動実行でスキップしたい場合は `VERIFY_SKIP_SSH=true` を設定してください。

## 日常運用タスク

### システム状態確認

#### 全体状態の確認

```bash
# 確認フェーズ（簡易確認）
make phase5
```

この確認でチェックする項目：
- ArgoCDアプリ一覧
- Cloudflaredの存在確認

#### 詳細な検証

```bash
# 主要コンポーネント確認
kubectl get nodes -o wide
kubectl get applications -n argocd
kubectl get pods -A | grep -v Running | head -20
```

### クラスター管理

#### ノードへのアクセス

```bash
# 特定ノードへのSSH
ssh k8suser@192.168.122.10  # Control Plane
ssh k8suser@192.168.122.11  # Worker1
ssh k8suser@192.168.122.12  # Worker2
```

#### ノード管理

```bash
# ノード状態確認
kubectl get nodes -o wide

# ノードの詳細情報
kubectl describe node <node-name>

# ノードのメンテナンスモード
kubectl drain <node-name> --ignore-daemonsets
kubectl uncordon <node-name>
```

#### ノード設定の運用（/etc書き換え）

Harbor連携のため、以下のDaemonSetがノードの`/etc`を更新します。

- `manifests/infrastructure/gitops/harbor/containerd-config.yaml`
- `manifests/infrastructure/gitops/harbor/harbor-node-hostaliases.yaml`

**注意点**:
- `hostPath`と`privileged`を使用するため、影響範囲はノード全体
- 変更内容は`/etc/hosts`と`/etc/containerd/config.toml`
- 反映後の挙動確認は`kubectl get ds -n kube-system | grep harbor`で実施

### アプリケーション管理

#### ArgoCD操作

```bash
# ArgoCD UIへのアクセス
kubectl port-forward svc/argocd-server -n argocd 8080:443
# URL: https://localhost:8080

# Application一覧
kubectl get applications -n argocd

# 手動同期
kubectl patch application <app-name> -n argocd \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# 同期状態確認
kubectl get application <app-name> -n argocd -o jsonpath='{.status.sync.status}'
```

#### Harbor レジストリ管理

```bash
# Harbor UIへのアクセス（内部）
# 事前に内部CAを端末に信頼させる
kubectl port-forward svc/harbor-core -n harbor 8081:80
# URL: https://harbor.internal.qroksera.com
# 直接アクセスできない場合は http://localhost:8081 を使用

# イメージのプッシュ（内部）
docker tag myapp:latest harbor.internal.qroksera.com/sandbox/myapp:latest
docker push harbor.internal.qroksera.com/sandbox/myapp:latest

# イメージの確認（内部）
curl -X GET "https://harbor.internal.qroksera.com/api/v2.0/projects/sandbox/repositories" \
  -H "accept: application/json" \
-u admin:<harbor-admin-password>
```

### GitHub Actions Runner管理

#### Runner状態確認

```bash
# Runner ScaleSet一覧
helm list -n arc-systems | grep runners

# Runner Pods確認
kubectl get pods -n arc-systems | grep runner

# 特定RunnerScaleSetの詳細
helm get values <runner-name> -n arc-systems
```

RunnerはGitOps管理ではなく、`add-runner.sh` による作成運用とします。
内部CAは `add-runner.sh` で Runner(dind) に自動配布されます。
`manifests/platform/ci-cd/github-actions/` には controller と RBAC のみを保持します。

#### Runner追加・削除

```bash
# 個別Runner追加
make add-runner REPO=repository-name

# 一括Runner追加（settings.tomlから）
make add-runners-all

# Runner削除
helm uninstall <runner-name> -n arc-systems
```

#### Runner設定変更

```bash
# minRunners/maxRunners変更
helm upgrade <runner-name> \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --namespace arc-systems \
  --set minRunners=2 \
  --set maxRunners=5 \
  --wait
```

### Secret管理

#### External Secrets確認

```bash
# ClusterSecretStore状態
kubectl get clustersecretstore
kubectl describe clustersecretstore pulumi-esc-store

# ExternalSecret一覧
kubectl get externalsecrets -A

# Secret同期状態
kubectl get externalsecret <name> -n <namespace> -o jsonpath='{.status.conditions}'
```

bootstrap用ExternalSecretは初回導入のみ使用し、通常運用では適用しません。

#### Secret更新

```bash
# Pulumi ESCでの更新後、強制同期
kubectl annotate externalsecret <name> -n <namespace> \
  force-sync="$(date +%s)" --overwrite
```

### ストレージ管理

#### PersistentVolume確認

```bash
# PV/PVC状態
kubectl get pv
kubectl get pvc -A

# ストレージ使用量
kubectl exec -n <namespace> <pod-name> -- df -h
```

#### ストレージクリーンアップ

```bash
# 未使用PVCの削除
kubectl delete pvc <pvc-name> -n <namespace>

# Failed状態のPVクリーンアップ
kubectl delete pv <pv-name>
```

### ネットワーク管理

#### LoadBalancer IP管理

```bash
# 割り当て済みIP確認
kubectl get svc -A | grep LoadBalancer

# MetalLB設定確認
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
```

#### Gateway管理

```bash
# Gateway/HTTPRoute一覧
kubectl get gateway -A
kubectl get httproute -A

# NGINX Gateway Fabric状態
kubectl get pods -n nginx-gateway
kubectl logs -n nginx-gateway deployment/ngf-nginx-gateway-fabric
kubectl logs -n nginx-gateway deployment/nginx-gateway-nginx
```

### 監視・ログ

#### 運用ポリシー

- 監視対象は「コントロールプレーン」「主要アプリ」「ストレージ」「Gateway」に分ける
- 重要アラートの一次切り分けは 15 分以内に実施する
- 重要イベントは `automation/run.log` と合わせて記録する

#### ログ確認

```bash
# 実行ログ
cat automation/run.log

# Pod ログ
kubectl logs -n <namespace> <pod-name>
kubectl logs -n <namespace> <pod-name> --previous  # 前回のログ

# ノードログ（SSH経由）
ssh k8suser@192.168.122.10 'journalctl -u kubelet -f'
```

#### メトリクス確認

```bash
# リソース使用状況
kubectl top nodes
kubectl top pods -A

# イベント確認
kubectl get events -A --sort-by='.lastTimestamp'
```

### バックアップとリストア

このホームラボ環境では、消失して困るデータがない前提のためバックアップは任意です。
必要になった場合のみ、以下の手順を有効化してください。

#### 設定バックアップ

```bash
# Kubernetesリソースのバックアップ
kubectl get all -A -o yaml > backup-all-resources.yaml

# ArgoCDアプリケーション設定
kubectl get applications -n argocd -o yaml > backup-argocd-apps.yaml

# Secret（注意: 暗号化して保存）
kubectl get secrets -A -o yaml | \
  gpg --encrypt --recipient your-email > backup-secrets.yaml.gpg
```

#### Terraformステートバックアップ

```bash
cd automation/infrastructure
cp terraform.tfstate terraform.tfstate.backup
```

### メンテナンス作業

#### VM再起動

```bash
# 計画的再起動
kubectl drain k8s-worker1 --ignore-daemonsets
sudo virsh shutdown k8s-worker1-ec56d7ba
sudo virsh start k8s-worker1-ec56d7ba
kubectl uncordon k8s-worker1
```

#### クラスターアップグレード

```bash
# kubeadm アップグレード（Control Plane）
ssh k8suser@192.168.122.10
sudo apt update
sudo apt-mark unhold kubeadm
sudo apt-get update && sudo apt-get install -y kubeadm=<version>
sudo apt-mark hold kubeadm
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply v<k8s-version>
```

バージョン指定は `docs/kubernetes-upgrade-guide.md` の手順に合わせて更新してください。

#### 証明書更新

```bash
# 証明書有効期限確認
ssh k8suser@192.168.122.10 'kubeadm certs check-expiration'

# 証明書更新
ssh k8suser@192.168.122.10 'sudo kubeadm certs renew all'
```

### トラブルシューティング

#### Pod が起動しない

```bash
# Pod状態詳細
kubectl describe pod <pod-name> -n <namespace>

# イベント確認
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# ログ確認
kubectl logs <pod-name> -n <namespace>
```

#### ノードが NotReady

```bash
# ノード詳細確認
kubectl describe node <node-name>

# kubeletステータス
ssh k8suser@<node-ip> 'sudo systemctl status kubelet'

# kubeletログ
ssh k8suser@<node-ip> 'sudo journalctl -u kubelet -n 100'
```

#### ArgoCD同期失敗

```bash
# Application詳細
kubectl describe application <app-name> -n argocd

# 手動同期（強制）
argocd app sync <app-name> --force --prune

# リソース差分確認
argocd app diff <app-name>
```

### パフォーマンス最適化

#### リソース最適化

```bash
# リソース使用状況分析
kubectl top pods -A --sort-by=memory
kubectl top pods -A --sort-by=cpu

# HPA（Horizontal Pod Autoscaler）設定
kubectl autoscale deployment <deployment-name> \
  --cpu-percent=70 --min=1 --max=10
```

#### ネットワーク最適化

```bash
# DNSパフォーマンス確認
kubectl exec -it <pod-name> -- nslookup kubernetes.default

# Service Mesh検討（将来）
# Istio, Linkerd等の導入を検討
```

### セキュリティ運用

#### 運用ポリシー

- 権限は最小化し、ClusterRole の追加は運用レビューを通す
- Secret は Git に置かず、External Secrets 経由で管理
- 例外で手動作成した Secret は必ず GitOps へ回収する
- PSA ラベルは `manifests/core/namespaces.yaml` で管理する

#### Pod セキュリティ

```bash
# Namespace の Pod Security 設定確認
kubectl get ns -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.pod-security\\.kubernetes\\.io/enforce}{"\n"}{end}'
```

#### セキュリティスキャン

```bash
# イメージスキャン（Harborで自動実行）
# Harbor UIでスキャン結果確認

# Pod Security Policy確認
kubectl get psp
kubectl describe psp <policy-name>
```

#### RBAC管理

```bash
# ServiceAccount一覧
kubectl get serviceaccounts -A

# Role/ClusterRole確認
kubectl get roles -A
kubectl get clusterroles

# 権限確認
kubectl auth can-i <verb> <resource> --as=<user>
```

#### ネットワーク制御

```bash
# NetworkPolicyの有無確認
kubectl get networkpolicy -A
```

### 定期メンテナンスチェックリスト

#### 日次

- [ ] `make phase5` で確認
- [ ] Pod異常の有無確認
- [ ] ログエラーチェック

#### 週次

- [ ] ノード/アプリ状態の詳細確認
- [ ] ストレージ使用量確認
- [ ] バックアップ実行

#### 月次

- [ ] 証明書有効期限確認
- [ ] セキュリティアップデート確認
- [ ] リソース使用傾向分析

## 緊急時対応

### クラスター復旧

```bash
# 完全再構築
make all

# 部分再構築
make phase2  # インフラのみ
make phase3  # GitOps準備のみ
make phase4  # GitOpsアプリ展開のみ
```

### データリカバリ

```bash
# バックアップからのリストア
kubectl apply -f backup-all-resources.yaml

# Secret復号とリストア
gpg --decrypt backup-secrets.yaml.gpg | kubectl apply -f -
```

## サポート

問題が解決しない場合：

1. ログの収集: `cat automation/run.log`
2. 診断情報: `kubectl get pods -A | grep -v Running | head -20`
3. [GitHub Issues](https://github.com/ksera524/k8s_myHome/issues)で報告
