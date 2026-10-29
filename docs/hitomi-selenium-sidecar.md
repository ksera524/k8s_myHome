# hitomi 収集時だけ Selenium を起動する

`hitomi-monitor` CronJob の native sidecar として Selenium を起動する。
収集は従来どおり JST 02:55 / 06:55 / 10:55 / 14:55 / 18:55 / 22:55。
常駐 Selenium Deployment / Service / Application は廃止し、`tools` namespace 自体は残す。

## 起動と終了

正本は [hitomi の manifest](../manifests/apps/hitomi/manifest.yaml)。

1. `initContainers` の `selenium` を `restartPolicy: Always` で起動する。
2. Selenium イメージ内の `/opt/bin/check-grid.sh` が Grid の `value.ready=true` を確認する。
   startupProbe が成功するまで hitomi は起動しない。単に HTTP 200 が返るだけでは開始しない。
3. hitomi は `http://127.0.0.1:4444/wd/hub` へ接続する。
4. hitomi の正常終了・異常終了・Job の deadline 到達時には Kubernetes が sidecar も停止する。

`Forbid`、`backoffLimit: 0`、`activeDeadlineSeconds: 7200` を維持する。
Selenium の起動待ちも Job の2時間上限に含まれる。probe は約5分で失敗判定して
sidecar を再起動するが、準備できないまま hitomi を開始しない。
ブラウザ再起動中の収集成功を保証するものではなく、失敗項目の再試行は既存の DB 履歴を使う。

Selenium の版 `155.0-20261010` と CPU / memory の予約・上限は常駐時から維持する。
専用の `/dev/shm` は memory-backed emptyDir、上限1GiB。DB CA やアプリ Secret は
sidecar にマウントしない。外部 HTTP/HTTPS は hitomi Pod の既存 NetworkPolicy を共有する。
WebDriver 用 Service と Pod 間の4444/TCP許可は不要になる。

Kubernetes 1.33以降の native sidecar を前提とする。実クラスタは確認時点で1.36.0。
起動順と Job 終了時の扱いは [Kubernetes 公式](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/) を参照。

## 検証

```bash
mise exec -- automation/scripts/ci/validate.sh
mise exec -- python3 automation/scripts/ci/selenium-runtime.py
```

runtime 検証は Docker 上に一時 kind クラスタを作り、専用 kubeconfig / context を使う。
終了時にテストクラスタを削除し、本番には Job・Secret・通知を作成しない。
レンダリング済み CronJob の sidecar を使い、収集コンテナだけを模擬クライアントへ置き換える。

- startupProbe 後、リトライなしで WebDriver に接続し、Chrome のセッション作成・
  data URL の表示・タイトル取得・PNGスクリーンショット・セッション削除を確認する。
- 主処理の正常終了と異常終了のそれぞれで、Job が終端状態になり Selenium が停止することを確認する。
- startupProbe を強制失敗させ、主処理が起動せず deadline で sidecar も終了することを確認する。

これは実サイトの取得成功、AVIF デコード、通知配送、実クラスタの NetworkPolicy 適用の試験ではない。
通信許可の和集合は既存の `test_workload_networkpolicies.py` でも検証する。

## GitOps 切替

root の子 Application 削除、core のポリシー削除、hitomi の更新は別々に同期される。
sync wave だけで全 workload の切替順を保証しないため、**旧収集 Job が動いていない時間帯**に反映する。

```bash
kubectl -n sandbox get jobs
kubectl -n sandbox get cronjob hitomi-monitor -o jsonpath='{.status.active}'
kubectl -n sandbox get pods -l app=hitomi-monitor
```

CronJob の active と Pod の状態を確認する。
旧 Job が実行中なら終了まで待つ。次回の予定時刻までに同期できない場合は、Git で一時的に
CronJob を suspend する段階を分け、反映後に解除する。稼働中の旧 Job を残して
Selenium Application を削除すると、その収集の WebDriver 接続が失われる。

Git 反映後は次を確認する。

- `bootstrap-root` / `core` / `hitomi` が同期し、旧 `selenium` Application と Deployment / Service が消える。
- CronJob の接続先と initContainers が新定義になっている。既存 Job の Pod spec は更新されない。
- 次回収集で Selenium の起動完了後に hitomi が開始し、処理終了後は両コンテナが停止する。
- Job の終了結果と DB の業務上の失敗を分けて確認する。既存の取得失敗をこの変更で成功扱いにしない。
- 収集間の待機時間に Selenium の Running Pod が残らない。

省メモリ量は収集時間に依存する。2026-10-27 の常駐時に約766MiBを観測したが、
これを24時間一定の削減量として扱わない。
