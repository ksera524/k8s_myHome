# アプリケーションのPostgreSQL移行手順

設計は [構成レビュー](application-architecture-review-20261024.md)、実装・検証の現在地は [実装記録](application-implementation-status-20261024.md) を参照。
新しいworkloadの完成形は [切替用マニフェスト](../automation/examples/application-architecture/) にある。
既存Applicationはこのexamplesを参照していない。新コードを含むimageをHarborへ配備する前に、旧digestのまま新コマンドを有効にしないための配置である。

## 準備

1. アプリ4 repoの変更を確定し、API/batch/viewer/hitomi/cameraの5 imageをCIで作成する。検証用ローカルタグは `architecture-20261024`。
2. Harborへのpush結果のdigestを記録し、各 `manifests/apps/<app>/kustomization.yaml` のimage tag/digestを同時に更新する。ローカルのimage config IDをregistryのmanifest digestとして使わない。
3. 新DB、ESO、CA配布、NetworkPolicy、S3 HTTPS/DNS/証明書/CORSの基盤変更を同期する。共有roleは既存 `app`、入力資格情報は既存 `postgresql.password`。
4. `application-postgresql` Secret/ConfigMap、`shared-postgresql-ca`、4 DBの所有者/接続制限を確認する。app上限80、クラスタ100、migration含む見積りは [接続予算](shared-postgresql.md)。
5. 既存のpgBackRest backupと復元手順を維持する。別媒体backupは実施できないとの利用者指示により今回の対象外とし、切替条件から外す。

merge後の基盤確認と最初の切替内容は [api-hub切替の第1段階](application-cutover-api-hub-20261024.md) を参照。

RTSP値の移行用Secret `sandbox/home-camera` は既存値からbootstrap済み。値は出力していない。
再作成やローテーションには以下を使う。外部Secret管理の新しい資格情報項目は不要。

```bash
# 既定はserver dry-run。値だけを入れた0600ファイルを使う場合
nix develop --command python3 automation/scripts/diagnostics/camera-secret-bootstrap.py --rtsp-file /secure/rtsp-url
# 反映時だけ --apply を付ける
```

## GitOpsへの反映順序

examples各appの `manifest.yaml` を、対応する既存 `manifests/apps/<app>/manifest.yaml` へ移す。
各appのkustomizationのimage digest更新も同じ変更に含める。新しい製品や独立Applicationは追加せず、既存のApplicationがAPI/workerを所有する。
各migrationはPreSync Job、poolは1接続、準備待ちを含めdeadline 900秒。DDLは追加変更のみで、実行roleもapp。

1. **api-hub**：migration → API → 通知worker。既存のS3/Slack同期APIも残す。DB停止時もS3 proxy/署名APIの起動を妨げない。
2. **media**：旧 `hitomi-pdf-monitor` の実行中Jobを完了させる。plannerは `suspend: true` で新API/workerを起動し、[明示import Job](../automation/examples/media-import/README.md)を完了させる。通常同期はimportを実行しない。importはS3を変更せず、PDF/previewの対応、サイズ、ETag、保存時刻、既存keyを登録する。元ID不明の動画はlegacyとして登録し、順位から元IDを推測しない。
3. **viewer**：examples/accessのHTTPRouteを既存 `manifests/access/hitomi-upload-viewer/manifest.yaml` に反映し、`/media/` をmedia-apiへ向ける。viewerの新imageと `MEDIA_CATALOG=true` / `DIRECT_MEDIA_DELIVERY=true` を有効にする。
4. import件数と元一覧を比較し、確認後にmedia plannerの `suspend` をfalseにする。既定の対象日は**JSTの前日**、実行は00:50/07:50 JST。特定日を取り込む場合は `--plan YYYYMMDD`。
5. **hitomi**：旧Jobを完了後、migration → outbox dispatcher → CronJobを反映する。各sourceの初回に見えている項目はbaselineとなり、既存分を一斉送信しない。以後はRSSから消えた未完了項目もDBから処理する。
6. **camera**：旧CronJobをsuspendし、実行中Jobを完了させる。新StatefulSetは最初 `replicas: 0`。旧録画が動いていないこととspool PVC/Secretを確認してから1へ変更する。Podを強制削除して旧writerと新writerを重ねない。

この順序の同期を個別に確認する。同じsync waveの全Applicationが依存先の切替完了を自動で待つとは扱わない。

## 動作確認

- 各Podの担当DB、`current_user=app`、TLSのverify-full、CA mountを確認する。pool上限と実接続数を照合する。
- 通知は同じproducer/event/channelの再受付で同じIDになる。202は永続受付、配送済みは `GET /notifications/{id}` の `sent`。429待機・再起動からの回復を確認する。
- `uncertain` はSlackが受け取った可能性がある。Slack側を確認してから `POST /notifications/{id}/retry` を使う。file IDも結果に残る。
- カタログ一覧・ランダム・ページ送りでS3 Listを呼ばないこと、preview欠損だけを再取得できることを確認する。import直後や結果保存前停止からの回復では `形式未確認` の表示があり、存在確認と内容検証を区別する。
- 期限切れは自動で再取得しない。UIの再取得は明示的な操作。元URL不明のlegacy動画は自動修復できない。
- PDF/動画で200/206、Content-Range、ETag、CORSを確認する。動画の再生位置を変え、期限切れを再現して署名再発行後の再開を確認する。PDFのリンクはクリックごとに新しく発行される。長時間開いたPDFの再取得が拒否された場合はカタログのリンクから開き直す。
- 同じ端末とobjectで新S3 HTTPS経路と旧proxyを再計測する。[変更前測定](performance/20261024/README.md) は端末描画や新Gateway経路の改善率を示すものではない。
- cameraはJST 19:00〜翌09:00、300秒を目安にsegment化する。codec copyの境界はkeyframe間隔に依存する。記録開始はsegmentファイルを開いたUTC秒、終了は実ファイルのdurationから計算し、予定の300秒を実録画時間として保存しない。
- cameraのDB/S3を止めても録画が進み、復帰後に送信・spool削除できることを確認する。spool上限80GiB/要求PVC100GiB。空き2GiB未満でも止まり、未送信を自動削除しない。NFS自体が停止した場合は録画も継続できない。
- cameraのmetricsは9090、既存VictoriaMetricsのannotation scrapeで収集する。滞留1時間、spool停止、不完全segment、録画時間帯の停止を既存Alertmanagerで検知する。

## 戻す場合

カタログの配信だけを戻す場合はmedia APIを `MEDIA_DIRECT_DELIVERY=false` にし、`PUBLIC_API_BASE_URL` のHTTPS api-hub proxyを利用する。旧画面ではviewerの `DIRECT_MEDIA_DELIVERY=false` を使う。
新形式の動画は旧S3日付一覧に現れないため、カタログを単純に無効にする方法は完全な表示互換を持たない。新writerを停止し、DBとobjectを残したまま既存カタログの読み取りを維持する。

cameraは新recorderを0へ変更し、終了を確認してから旧CronJobを再開する。spoolを消さず、新uploaderを残して滞留データを送ることもできる。
DBのdown migrationやS3 objectの削除は切戻しに含めない。

DB restoreでは通知worker/outboxを先に止め、Slackの外部副作用とDB復元時点を照合してから再開する。
hitomiのevent IDはsource/恒久ID/更新期間から生成し、DB連番の再利用による衝突を避けるが、Slack成功後のDB巻戻りによる再送可能性は残る。
