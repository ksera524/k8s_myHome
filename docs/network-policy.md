# NetworkPolicy の運用

[Flannel](../automation/infrastructure/main.tf) に加え、
[kube-network-policies](../manifests/infrastructure/networking/kube-network-policies/manifest.yaml) が Linux ノード上でポリシーを実行します。
宣言済みの controller は全 Linux ノードが対象で、初回カナリア導入途中の構成ではありません。

## ポリシーの所有者

| 正本 | 選択する対象と許可 |
|---|---|
| [core/networkpolicies.yaml](../manifests/core/networkpolicies.yaml) | Gateway → RustFS:9001、sandbox の `app=api-hub` → RustFS:9000 |
| [RustFS lifecycle](../manifests/platform/rustfs/lifecycle-networkpolicy.yaml) | 同 namespace の lifecycle Job → RustFS:9000 |
| [PostgreSQL](../manifests/platform/shared-postgresql/credentials.yaml) | database 内 Pod、harbor の `app=harbor`、observability の Grafana → DB（namespace 外は TCP 5432） |
| [Loki](../manifests/platform/observability/logging-networkpolicy.yaml) | Grafana / Alloy → Loki:3100 |

全 namespace 一律の default-deny / egress 制限は宣言されていません。
RustFS は api-hub と lifecycle Job の両方に S3 の許可があり、「api-hub 以外は一切接続できない」という説明は不正確です。

## controller の設定と限界

- `--disable-nri=true`：Pod 情報は API informer から取得します。
- `--strict-mode=true`：既存接続への影響も含めて更新時に確認します。
- `--fail-open=true`：controller / queue 障害時の可用性を優先します。常時遮断を保証する境界ではありません。
- nftables / NFQUEUE とホストネットワークを使います。readiness の成功は通信遮断の実測を代替しません。

実際の引数・権限・マウントは上記 DaemonSet が正本です。controller の利用不能と metrics 欠落は
[alert-rules.yaml](../manifests/platform/observability/config/alert-rules.yaml) に監視があります。

## 許可を追加するとき

[アクセス追加](access.md#新しく到達可能な-api-を追加する手順) と合わせて、宛先 namespace / Pod selector、
接続元 namespace / Pod selector、Pod の待受 port を指定します。
同じ peer に namespaceSelector と podSelector を書くと両方を満たす対象、別の peer に書くとどちらかを満たす対象です。

既存の許可は合算されるため、狭いポリシーを足しても別の広い許可は取り消せません。
Gateway 経由の backend から見た接続元は NGINX Pod です。NetworkPolicy で HTTP パスや利用者の認可を表現しません。

## 検証と切り戻し

```bash
kubectl -n kube-system get ds kube-network-policies
kubectl get networkpolicy -A
kubectl -n kube-system logs daemonset/kube-network-policies --tail=100
```

許可された実アプリ経由の操作、無関係な Pod からの Service IP / Pod IP への接続拒否を複数ノードで確認します。
port-forward やノード発の通信だけでは Pod 間の拒否試験になりません。HTTP 403 はアプリへの到達を意味します。
検証 Pod に本番 Service と同じラベルを付けて、誤って Service の配信対象にしないでください。

通常の切り戻しはポリシー変更の Git revert と同期です。
GitOps 自体が通信障害で止まった場合は、影響する namespace と port に限定した暫定許可を検討し、
Git 修正の反映後に撤去します。controller 全停止は全ポリシーへ影響するため、局所修正と分けて判断します。
