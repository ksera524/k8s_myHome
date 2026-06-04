# Troubleshooting

この文書は current main の一次切り分け手順です。

## 最初に確認するもの

```bash
make phase5
kubectl get nodes -o wide
kubectl get applications -n argocd
kubectl get pods -A
kubectl get events -A --sort-by='.lastTimestamp'
```

実行ログです。

```text
automation/run.log
```

## `make all` / phase が失敗する

```bash
automation/scripts/ci/validate.sh
```

確認観点です。

- `automation/settings.toml` の必須項目が未設定ではないか
- Pulumi / GitHub 認証情報が不足していないか
- ホスト側のディスク容量が不足していないか
- `automation/run.log` に直近エラーがないか

## Node が `NotReady`

```bash
kubectl get nodes -o wide
kubectl describe node <node-name>
ssh k8suser@<node-ip> 'sudo systemctl status kubelet'
ssh k8suser@<node-ip> 'sudo journalctl -u kubelet -n 200'
```

## Pod が `Pending` / `CrashLoopBackOff`

```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

確認観点です。

- ImagePull エラー
- PVC 未バインド
- Secret / ConfigMap 不足
- probe 失敗
- node resource 不足

## ArgoCD が `OutOfSync` / `Degraded`

```bash
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd
kubectl get application <app-name> -n argocd -o jsonpath='{.status}'
```

確認観点です。

- 同一リソースが複数経路で apply されていないか
- CRD / Webhook など順序依存リソースの Sync Wave が正しいか
- `targetRevision` が `HEAD` のままか

## ExternalSecret が同期されない

```bash
kubectl get clustersecretstore
kubectl describe clustersecretstore pulumi-esc-store
kubectl get externalsecrets -A
kubectl describe externalsecret <name> -n <namespace>
```

主な原因です。

- Pulumi ESC 側キー名不一致
- `remoteRef.key` の誤り
- access token 期限切れ
- ExternalSecret の配置 domain が誤っている

## Gateway / Cloudflared が 502 または接続不可

```bash
kubectl get pods -n cloudflared
kubectl logs -n cloudflared deploy/cloudflared --since=10m
kubectl get gateway -A
kubectl get httproute -A
kubectl describe httproute <route-name> -n <namespace>
kubectl get certificate -A
```

確認観点です。

- Cloudflared origin が `nginx-gateway-nginx.nginx-gateway.svc.cluster.local:443` を指しているか
- `originServerName` と hostname が一致しているか
- `wildcard-external-tls` / `wildcard-internal-tls` が Ready か
- HTTPRoute の parentRefs と sectionName が正しいか

## Harbor へ push / pull できない

```bash
kubectl get pods -n harbor
kubectl logs -n harbor deployment/harbor-core --since=10m
docker login harbor.internal.qroksera.com
```

確認観点です。

- 端末に内部 CA を信頼登録しているか
- namespace 側の pull secret が最新か
- image tag が存在するか

## PVC が `Pending`

```bash
kubectl get pvc -A
kubectl describe pvc <pvc-name> -n <namespace>
kubectl get storageclass
kubectl get pods -n local-path-storage
```

## CronJob / Job が失敗する

```bash
kubectl get cronjobs -A
kubectl get jobs -A
kubectl describe job <job-name> -n <namespace>
kubectl get pods -n <namespace> -l job-name=<job-name>
kubectl logs -n <namespace> -l job-name=<job-name>
```

failed job の Pod が削除済みの場合、ログは取得できません。次回実行直後にログを取得します。

## Ubuntu 再起動後に接続できない

```bash
make recover
```

必要に応じて待機時間を上書きします。

```bash
RECOVER_MAX_WAIT_SECONDS=600 RECOVER_CHECK_INTERVAL_SECONDS=15 make recover
```
