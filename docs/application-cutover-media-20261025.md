# media切替の第2段階

## 第1段階の配備確認

api-hub #109のmerge後、ApplicationはSynced/Healthy、PreSync migrationはSucceeded。`api_hub._sqlx_migrations` の1/2が成功、API・通知workerは各1 replicaで稼働し、app / api_hub / TLSの接続を確認した。
S3 HTTPRouteの差分残りも解消し、rustfs-accessはSynced/Healthy。通知キューは空で、検証のためのSlack実送信は行っていない。
実PDF/MP4で署名GET・Range・CORS・旧proxyとの内容一致を確認した。[計測結果](performance/20261025/README.md)では速度の一貫した改善はまだ確認できていない。

## この段階の変更

- `media` DBへのPreSync migration、media API/worker、PostSync import、定期reconcileを既存hitomi-pdf Applicationへ追加する。
- 旧CronJobの同じ名前をplannerへ変更し、`suspend: true` のままにする。定期取得の再開はimport件数照合後の別段階で行う。
- 既存S3 keyを維持してカタログへ登録する。importはS3を書き換えず、取得ジョブも作らない。欠けたPDF/previewはmissingとして明示する。
- imageはmainに記録された公開済み `sha256:8c21c49a872466235e0e3cabd6bad6042f770c64ce0769409967586f4d7cdf45` を全コンテナに適用する。
- viewerと `/media/` 公開ルートはまだ切り替えない。APIは準備完了後にService経由で照合する。

準備時点の旧PDF Job `hitomi-pdf-monitor-2610241227` は成功済み、active Jobはない。merge前にも旧Jobが実行中でないことを確認する。Cronの次回実行前に反映されなかった場合は、起動した旧Jobの完了を待つ。
別媒体backupは利用者の指示で対象外。既存pgBackRestと復元手順は維持する。

## 同期後

2026-10-25の実機確認ではmigration version 1成功、media API/worker各1 replica起動を確認した。
一方、既存のCronJob health customizationが `suspend: true` をProgressingにするため、
同期はplannerのhealth待ちとなりPostSync importが未開始、assetsは0件だった。
CronJobの宣言された停止状態をHealthyとして評価するようargocd-configを修正する。
停止の有無はhealth messageとspec.suspendに残り、Gitとの差分は引き続きsync statusで検知する。
これは全CronJobに適用される。Jobの成否・定期処理停止の監視は別途必要であり、Healthyは実行成功を意味しない。
PostSyncの順序とplannerの停止は維持し、argocd-config同期後に待機中のhitomi-pdf同期とimportの完了を再確認する。
まだ取り込み完了・件数一致を確認していないため、viewer切替とplanner再開には進まない。

1. migration、media-apiの `/ready`、worker、PostSync importの成功とApplicationのSynced/Healthyを確認する。
2. PDF/preview/MP4の登録数、S3 keyの対応、保存期限と形式未確認の表示用属性を照合する。期限切れを除くready一覧と全状態一覧を混同しない。
3. カタログ一覧・ランダム・署名取得をServiceで確認し、S3一覧を閲覧時に要求しないことを確認する。
4. 照合後にviewerと公開ルートを切り替え、plannerを再開する。cameraの旧録画Jobにはこの段階で変更を加えない。

別途、既存hitomi JobがBackoffLimitExceededとなり、AVIFデコード非対応と旧HTTPS api-hubへのtimeoutを記録している。今回のmedia変更とは分け、hitomi切替時に内部Service接続と画像処理を確認する。
