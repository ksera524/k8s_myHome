# Observability

この文書は current main の observability 構成です。

## コンポーネント

| Component | Path | 用途 |
|---|---|---|
| VictoriaMetrics | `manifests/platform/observability/victoria-metrics.yaml` | metrics storage / UI |
| kube-state-metrics | `manifests/platform/observability/kube-state-metrics.yaml` | Kubernetes / CRD state metrics |
| vmalert | `manifests/platform/observability/vmalert.yaml` | アラート評価 / 状態保存 |
| Alertmanager | `manifests/platform/observability/alertmanager.yaml` | 発火中アラートの集約 / UI |
| observability access | `manifests/access/observability/` | internal HTTPRoute |

## Access

内部 UI は次で公開します。

```text
https://observability.internal.qroksera.com/vmui/
```

backend は `observability` namespace の `victoria-metrics:8428` です。

## CRD Metrics

kube-state-metrics の custom-resource-state metrics で次を取り込みます。

| Metric family | 対象 |
|---|---|
| `kube_argocd_application_*` | ArgoCD Application |
| `kube_externalsecret_status_condition` | ExternalSecret |
| `kube_gateway_status_condition` | Gateway |
| `kube_httproute_parent_status_condition` | HTTPRoute |
| `kube_certificate_status_condition` | cert-manager Certificate |

## Metrics API との違い

VictoriaMetrics は metrics storage です。`kubectl top nodes` / `kubectl top pods -A` が使う Kubernetes Metrics API とは別です。

`kubectl top` を使うには metrics-server が必要です。

## 確認コマンド

```bash
kubectl get pods -n observability
kubectl get httproute -n observability
kubectl get application observability observability-access -n argocd
```

Gateway 経由の確認例です。

```bash
curl -k -I https://observability.internal.qroksera.com/vmui/
```

## アラート

`observability` Application が vmalert と Alertmanager も管理します。
vmalert は既存 VictoriaMetrics を 30 秒間隔で評価し、Alertmanager に発火・復旧を送信します。
ルールと通知設定は `manifests/platform/observability/config/` に置き、
Kustomize の ConfigMap hash により変更時に Pod を更新します。

| 対象 | 発火条件 | 継続時間 |
|---|---|---|
| kube-state-metrics | scrape 失敗または up 欠損 | 5 分 |
| Node | Ready でない | 5 分 |
| Pod | Pending / Running / Unknown の Pod が Ready でない | 15 分 |
| コンテナ | 15 分間で 3 回以上の再起動 | 5 分 |
| Deployment | available replicas が desired replicas 未満 | 10 分 |
| PVC | Pending / Lost | 15 分 |
| ArgoCD Application | OutOfSync / Unknown | 15 分 |
| ArgoCD Application | Degraded / Missing / Unknown | 10 分 |
| ExternalSecret | Ready condition が false / unknown | 10 分 |
| Gateway | Programmed condition が false / unknown | 10 分 |
| Certificate | Ready condition が false / unknown | 15 分 |

`slack` receiver で全アラートの発火・復旧を Slack Incoming Webhook に通知します。
画面は port-forward で確認します。ターミナルを分けて実行してください。

```bash
kubectl -n observability port-forward svc/alertmanager 9093:9093
kubectl -n observability port-forward svc/vmalert 8880:8880
```

- Alertmanager: `http://localhost:9093/`（発火中アラート・silence）
- vmalert: `http://localhost:8880/vmalert/`（ルール・pending・評価エラー）

Alertmanager の silence / 通知履歴は emptyDir に保存するため Pod 再作成で消えます。
発火状態は vmalert から再送され、vmalert 自身の状態は VictoriaMetrics に保存・復元します。
Webhook URL は ExternalSecret で管理します（下記参照）。

CRD の condition 自体が欠損している場合は現行メトリクスから検出できません。
HTTPRoute は現在の exporter が最初の parent condition のみを収集するため、誤判定を避けるためルール対象外です。
Gateway の LoadBalancer IP、CronJob の直近実行結果、ARC 専用メトリクス、外形監視は後続課題です。
Cloudflared / Harbor / RustFS は汎用 Pod / PVC ルールで監視しますが、リソース自体の削除は検出しません。
監視基盤やクラスタ全体の停止は、このクラスタ内構成のみでは通知できません。

### ローカル検証

```bash
docker run --rm -v "$PWD/manifests/platform/observability/config:/config:ro" \
  victoriametrics/vmalert:v1.115.0 -rule=/config/alert-rules.yaml -dryRun
docker run --rm -v "$PWD/manifests/platform/observability/config:/config:ro" \
  --entrypoint /bin/amtool quay.io/prometheus/alertmanager:v0.28.1 \
  check-config /config/alertmanager.yaml
docker run --rm -v "$PWD:/work:ro" -w /work --entrypoint /bin/promtool \
  prom/prometheus:v3.2.1 test rules automation/tests/observability/alert-rules.test.yaml
```

デプロイ後は ArgoCD の Synced / Healthy と、vmalert 画面の評価エラーがないことを確認します。
ルール式を VMUI でも評価し、対象の時系列が存在することを確認してください。
2026-10-13 に live ルール評価と参照メトリクスの存在を確認済みです。
Alertmanager API から投入した `SlackNotificationTest` の発火・復旧通知は Slack で受信確認済みです。
実障害を発生させる試験は実施していません。

参考: [vmalert](https://docs.victoriametrics.com/victoriametrics/vmalert/)、
[Alertmanager 設定](https://prometheus.io/docs/alerting/latest/configuration/)。

### Slack 通知の有効化

1. Slack App の Incoming Webhooks を有効にし、通知先チャンネル用の Webhook を作成します。
2. Pulumi ESC の `ksera / k8s / secret` 環境に、`alertmanager-slack-webhook-url` を **secret 値**として登録します。
   値は Webhook URL 全体です。Git やチャットに貼り付ける必要はありません。
3. GitOps 反映後、`config-secrets` により `observability/alertmanager-slack` Secret が作成されたことを確認します。
4. `observability` Application を同期し、Alertmanager が Ready になったことを確認します。

```bash
kubectl -n observability wait --for=condition=Ready externalsecret/alertmanager-slack --timeout=120s
kubectl -n observability rollout status deployment/alertmanager
```

Secret が未登録の間は Alertmanager の Pod が起動できません。GitOps 反映前に ESC へ登録してください。
既存の sandbox 用 `slack` Bot token とは別の認証情報です。
通知先は Webhook に紐づくチャンネルを使うため、マニフェストの channel 指定は不要です。
Webhook の変更は ESC から Secret volume に反映されます（subPath は使用しません）。

初回通知は集約のため 30 秒待機し、同じグループの変化は 5 分間隔、未復旧時の再通知は 4 時間間隔です。
実機の受信確認では Alertmanager UI と Slack の両方で発火・復旧を確認してください。
送信失敗時は Alertmanager のログと `alertmanager_notifications_failed_total` を確認します。

参考: [Slack Incoming Webhooks の作成手順](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks/)。

## 週次 Slack レポート

`weekly-observability-report` CronJob が毎週月曜 09:00（`Asia/Tokyo`）に実行されます。
VictoriaMetrics の直近 7 日間を集計し、既存の `alertmanager-slack` Secret を使って同じ Slack チャンネルへ送信します。
Alertmanager の通知間隔・silence とは独立した定期レポートです。

- Node / Pod Ready、Deployment replica 不足、PVC Pending / Lost
- ArgoCD sync / health、ExternalSecret / Certificate Ready、Gateway Programmed
- コンテナ再起動回数の上位 5 件

状態は 5 分刻みのサンプルから「一度でも異常だった対象数 / 期間中に観測した対象数」を集計します。
アラートの `for` は適用せず、短時間のデプロイ中の状態も集計対象です。
同じ namespace・名前のリソースは再作成されてもまとめます。再起動は counter の `increase` による推定値です。
欠損データは正常とは判定せず「データなし」、API エラーは「取得失敗」と表示します。
部分的な収集停止や 5 分未満の異常は見落とし得るため、稼働率・障害件数を示すものではありません。
CPU / メモリ使用量はこのレポートの対象外です。PVC 容量は下記の現在値を追加しています。

処理時間の上限は 7 分、遅延実行の猶予は 1 時間、同時実行は禁止します。
取得失敗時は不完全なレポートを送った上で Job を失敗させます。
重複通知を減らすため Job の自動リトライは無効ですが、CronJob / Slack は厳密な一度だけの配信を保証しません。
失敗 Job は最大 3 件保持します。必要に応じてログを確認して手動実行してください。

```bash
kubectl -n observability get cronjob weekly-observability-report
# 手動実行も実際に Slack へ送信します。
kubectl -n observability create job --from=cronjob/weekly-observability-report weekly-report-manual-$(date +%s)
```

ローカルで本文だけ確認する場合（Slack へは送信しません）:

```bash
kubectl -n observability port-forward svc/victoria-metrics 18428:8428
# 別ターミナルで実行
VICTORIA_METRICS_URL=http://localhost:18428 \
  python3 -B manifests/platform/observability/scripts/weekly-report.py --dry-run
python3 -B -m unittest discover -s automation/tests/observability -p 'test_*.py'
```

### PVC の空き容量

kubelet `/metrics` を API server proxy 経由で 30 秒ごとに収集します。
ServiceAccount とクラスタ CA を使用し、容量 3 種のメトリクスのみ保存します。
週次レポートには現在の空き容量（GiB / %）、総容量、使用量（GiB / %）を全 PVC 分表示します。
同じ PVC が複数ノードにある場合は空き容量の最小値を採用し、重複を合算しません。

現在の `nfs-external` は共有ファイルシステムの統計を返します。
PVC の要求サイズに対する利用率でも、各ディレクトリ固有の使用量でもありません。
PVC 間の容量の合算はできません。予約領域等があるため、使用量と空き容量の和が総容量と一致しない場合もあります。

- 空き 20% 未満が 15 分継続: warning
- 空き 10% 未満が 15 分継続: critical（warning も併せて発火）
- kubelet scrape 失敗が 5 分継続: warning

容量のない PVC は「容量取得不可」と表示し、容量不足アラートは評価できません。
未マウント・ストレージ側の未対応なども原因となり得ます。
容量取得開始前の履歴はないため、容量欄は送信時点の値です。
