# Kubernetes / containerd の更新

入口は [Makefile](../Makefile)、実体は [upgrade/](../automation/scripts/upgrade/) です。
アプリ・chart の更新は [アプリ更新](application-auto-updates.md) に分けます。

## Kubernetes

`automation/settings.toml` の `[upgrade]` で `target_version` を明示します。
`apt_channel` が空なら対象版の minor から推定します。サンプルの古い版番号をそのまま更新先として使わず、
現在の Node 版、更新経路、対象パッケージを確認してください。

```bash
kubectl get nodes -o wide
make upgrade-safe
```

実際の順序は次です。

1. 事前ゲート（Node / 異常 Pod / ArgoCD の状態）
2. precheck（SSH 接続、状態表示、etcd snapshot、`kubeadm upgrade plan`）
3. control-plane 更新
4. worker 更新
5. postcheck
6. 事後ゲート

ゲート再試行の既定は 3 回 / 30 秒です。`run.sh` は親 shell に `get_config` がある場合だけ
`[upgrade].gate_retries` / `gate_retry_wait_seconds` を読みます。通常の Make 起動では
設定ロードが各 step の内側で行われるため、この 2 設定の変更がゲートへ反映されるとは扱いません。
`make upgrade` はゲートを含まない経路です。
`upgrade-precheck` は読み取り専用ではなく、etcd Pod 内の `/var/lib/etcd/etcd-snapshot-<時刻>.db` へ snapshot を作成します。
スクリプトはこれをホスト外へ退避しません。DB・オブジェクトなどの業務データは別にバックアップします。

分割する場合は順序を維持します。

```bash
make upgrade-precheck
make upgrade-control-plane
make upgrade-workers
make upgrade-postcheck
```

更新はサポートされる minor ごとに計画し、バックアップの復元方法を先に準備します。
スクリプトの成功だけでサービスの実操作や復元可能性が保証されるわけではありません。

## containerd

[containerd-upgrade-safe.sh](../automation/scripts/upgrade/containerd-upgrade-safe.sh) は **指定した 1 ノード**を処理します。
`make containerd-safe` だけで全ノードを順に更新するものではありません。

設定キーは `containerd_package`、`containerd_source_channel`、`containerd_current_version`、
`containerd_target_version`、`containerd_canary_node` です。current_version は rollback 先なので、実機と配布元の版を照合します。

```bash
make containerd-precheck
make containerd-safe
# カナリア確認後に次のノードを明示
./automation/scripts/upgrade/containerd-upgrade-safe.sh --node <node-name>
```

cordon → `drain --ignore-daemonsets --delete-emptydir-data` → package 更新 → containerd/kubelet 再起動 →
CRI / Node Ready → uncordon → post gate を実行します。emptyDir のデータは破棄されます。
失敗時に自動 rollback / uncordon する実装ではないため、ノードと処理段階を確認します。

```bash
./automation/scripts/upgrade/containerd-upgrade-safe.sh --rollback --node <node-name>
make containerd-precheck
./automation/scripts/upgrade/upgrade-gate-check.sh --phase post
```

rollback も drain と再起動を伴います。設定した旧パッケージが取得でき、既存設定と互換であることが前提です。
更新後は [日常運用](operations.md) の確認に加え、Harbor、S3、DB、内部 URL の実操作を確認します。
