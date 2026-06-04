# Upgrade

この文書は Kubernetes と containerd の更新手順です。

## 前提

- Kubernetes version は `automation/settings.toml` の `[kubernetes]` と `[upgrade]` を確認します。
- Kubernetes は 1 minor version ずつ更新します。
- 更新前後で ArgoCD Application が `Synced/Healthy` であることを確認します。

## Kubernetes upgrade

推奨入口です。

```bash
make upgrade-safe
```

`upgrade-safe` は次を実行します。

1. 事前ゲート
2. 通常アップグレード
3. 事後ゲート

ゲートは Node Ready、異常 Pod、ArgoCD 全 Application の `Synced/Healthy` を確認します。

## 分割実行

必要な場合は段階ごとに実行します。

```bash
make upgrade-precheck
make upgrade-control-plane
make upgrade-workers
make upgrade-postcheck
```

## 設定例

```toml
[upgrade]
target_version = "v1.33.7"
apt_channel = "v1.33"
gate_retries = 3
gate_retry_wait_seconds = 30
```

## containerd 更新

containerd は本番外で検証し、本番は 1 node ずつ段階適用します。

事前診断です。

```bash
make containerd-precheck
```

カナリア更新です。

```bash
make containerd-safe
```

設定例です。

```toml
[upgrade]
containerd_package = "containerd.io"
containerd_source_channel = "docker"
containerd_current_version = "1.7.28-0ubuntu1~24.04.2"
containerd_target_version = "2.2.3-1~ubuntu.24.04~noble"
containerd_canary_node = "k8s-worker2"
```

## containerd rollback

```bash
./automation/scripts/upgrade/containerd-upgrade-safe.sh --rollback
```

rollback 後は次を実行します。

```bash
make containerd-precheck
./automation/scripts/upgrade/upgrade-gate-check.sh --phase post
```

## 完全再構築

安全優先で既存 cluster を作り直す場合です。

```bash
make all
make phase5
```

## ログ確認

```bash
tail -n 200 automation/run.log
```

## 失敗時の確認

```bash
kubectl get nodes -o wide
kubectl get applications -n argocd
kubectl get pods -A
kubectl get events -A --sort-by='.lastTimestamp'
```
