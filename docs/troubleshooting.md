# トラブルシューティングガイド

## 概要

このガイドは、k8s_myHome の現行構成（App-of-Apps + GitOps）で発生しやすい問題の切り分け手順をまとめたものです。

## このガイドの範囲

- 対象: 障害時の一次切り分け、主要コンポーネントの復旧、ログ収集
- 非対象: 日常運用は `docs/operations-guide.md`、初期構築は `docs/setup-guide.md`、アップグレードは `docs/kubernetes-upgrade-guide.md`

## まず最初に実行する確認

```bash
# 検証フェーズ
make phase5

# 実行ログ
cat automation/run.log
```

Control Plane 上で直接確認する場合:

```bash
ssh k8suser@192.168.122.10
kubectl get nodes
kubectl get applications -n argocd
kubectl get pods -A
```

## 典型障害と対処

### 1. `make all` / `make phaseX` が失敗する

```bash
# 直近エラーの確認
cat automation/run.log

# 必須ツール確認
command -v shellcheck
command -v yamllint
command -v kustomize

# CI相当チェック
automation/scripts/ci/validate.sh
```

確認ポイント:

- `automation/settings.toml` の必須項目が未設定
- Pulumi / GitHub 認証情報の不足
- ホスト側のディスク容量不足

### 2. ノードが `NotReady`

```bash
kubectl get nodes -o wide
kubectl describe node <node-name>

ssh k8suser@<node-ip> 'sudo systemctl status kubelet'
ssh k8suser@<node-ip> 'sudo journalctl -u kubelet -n 200'
```

復旧の第一手:

```bash
ssh k8suser@<node-ip> 'sudo systemctl restart containerd && sudo systemctl restart kubelet'
```

### 3. Pod が `Pending` / `CrashLoopBackOff`

```bash
kubectl get pods -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

切り分け観点:

- ImagePull エラー（レジストリ認証、タグ不整合）
- PVC 未バインド（StorageClass/PV不足）
- Secret/ConfigMap 不足

### 4. ArgoCD が `OutOfSync` / `Degraded`

```bash
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd
kubectl get application <app-name> -n argocd -o jsonpath='{.status}'

# ハードリフレッシュ
kubectl patch application <app-name> -n argocd \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

`OutOfSync` が続く場合:

- マニフェストが複数経路で apply されていないか
- CRD/Webhook など順序依存リソースの Sync Wave を誤っていないか

`argocd-applicationset-controller` が `CrashLoopBackOff` の場合:

```bash
kubectl get crd applicationsets.argoproj.io
kubectl logs -n argocd deployment/argocd-applicationset-controller --tail=120
```

`no matches for kind "ApplicationSet"` が出る場合は CRD 欠落です。復旧手順:

```bash
kubectl apply --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.3.0/manifests/crds/applicationset-crd.yaml
kubectl rollout restart deployment argocd-applicationset-controller -n argocd
kubectl rollout status deployment argocd-applicationset-controller -n argocd --timeout=180s
```

### 5. ExternalSecret が同期されない

```bash
kubectl get clustersecretstore
kubectl describe clustersecretstore pulumi-esc-store

kubectl get externalsecrets -A
kubectl describe externalsecret <name> -n <namespace>

# 再同期トリガー
kubectl annotate externalsecret <name> -n <namespace> \
  force-sync="$(date +%s)" --overwrite
```

`SecretSyncedError` の主因:

- Pulumi ESC 側キー名不一致
- `remoteRef.key` の誤り
- トークン期限切れ

### 6. Harbor へ push できない

```bash
# ログイン（内部FQDN）
docker login harbor.internal.qroksera.com

# Harbor 側の状態
kubectl get pods -n harbor
kubectl logs -n harbor deployment/harbor-core
```

確認ポイント:

- 端末に内部 CA を信頼登録できているか
- namespace 側の pull secret が最新か

### 7. 外部公開が 502 / 接続不可（Cloudflared + Gateway）

```bash
kubectl get pods -n cloudflared
kubectl logs -n cloudflared deploy/cloudflared --since=10m

kubectl get gateway -A
kubectl get httproute -A
kubectl describe httproute <route-name> -n <namespace>

kubectl get certificate -A
kubectl describe certificate <name> -n <namespace>
```

確認ポイント:

- Cloudflared origin が `nginx-gateway-nginx.nginx-gateway.svc.cluster.local:443` を指しているか
- `originServerName` が公開ホスト名と一致しているか
- `wildcard-external-tls` が Ready か

### 8. LoadBalancer IP が割り当てられない

```bash
kubectl get svc -A | grep LoadBalancer
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
kubectl logs -n metallb-system deployment/controller
```

### 9. Runner がジョブを拾わない（ARC）

```bash
kubectl get pods -n arc-systems
helm list -n arc-systems
helm get values <runner-name> -n arc-systems
```

確認ポイント:

- `minRunners` が 1 以上か
- GitHub 側 repository/organization の Runner 権限が正しいか

### 10. PVC が `Pending`

```bash
kubectl get pvc -A
kubectl describe pvc <pvc-name> -n <namespace>
kubectl get storageclass
kubectl describe storageclass local-path
kubectl get pods -n local-path-storage
```

## ログ収集テンプレート

```bash
#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="k8s-debug-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOG_DIR"

make phase5 > "$LOG_DIR/phase5.txt" 2>&1 || true
kubectl get nodes -o wide > "$LOG_DIR/nodes.txt"
kubectl get applications -n argocd > "$LOG_DIR/applications.txt"
kubectl get pods -A > "$LOG_DIR/pods.txt"
kubectl get events -A --sort-by='.lastTimestamp' > "$LOG_DIR/events.txt"
cp automation/run.log "$LOG_DIR/run.log" 2>/dev/null || true

tar czf "$LOG_DIR.tar.gz" "$LOG_DIR"
echo "ログ収集完了: $LOG_DIR.tar.gz"
```

## それでも解決しない場合

1. `automation/run.log` と上記ログ収集アーカイブを保存
2. 再現手順（いつ、何を実行したか）を時系列で整理
3. [GitHub Issues](https://github.com/ksera524/k8s_myHome/issues) に報告
