# viewer切替とmedia planner再開

## 前提の実機確認

#111のargocd-config反映後、停止中plannerのhealth待ちが解消した。
hitomi-pdfのmigrationとPostSync importはSucceeded、ApplicationはSynced/Healthy。
media API/workerは各1 replica Ready、共有app roleからmediaへのTLS接続を確認した。

- S3一覧をcontinuation tokenで全ページ取得し、DBの既存キー・サイズと全件比較した。
- PDF 1,509、preview 1,509、動画295、合計3,313件。S3側のみ・DB側のみ・サイズ不一致はいずれも0件。
- importによるingest_jobsは0件。不必要な再取得は起動していない。
- 期限は全件stored_at + 30日。形式検証済みは0件であり、importは形式検証を意味しない。
- Serviceのport-forward経由でカタログを全ページ取得。PDF 16ページ/1,509件、動画3ページ/295件、ID重複なし。各kindのrandom 5件はready一覧内に存在。
- PDFと動画それぞれのURL発行はS3 HTTPSを返し、実GETのRange 1024–2047が206/1,024 bytes、viewer originのCORSを確認した。
- port-forward経由の一覧1ページは約34–90 ms。公開Gateway経由・実ブラウザの描画時間やファイル本体の速度改善を示す測定ではない。

## この変更

viewerのMEDIA_CATALOGとDIRECT_MEDIA_DELIVERYをtrueにし、同じhostの `/media/` をmedia-apiへ渡す。
既存の公開済みviewer digestを維持する。定期plannerを00:50/07:50 JSTに再開し、既定で前日分を計画する。
初回のplanner/worker実行結果は反映後に確認する。旧PDF Jobのactiveは0件だった。

## 反映後の確認

1. hitomi-upload-viewer-accessのHTTPRouteがAccepted/ResolvedRefsとなり、公開hostの `/media/assets` がJSONを返す。
2. viewerのconfig.jsに両flagが反映され、一覧・PDFリンク・動画のRange/シークを確認する。
3. plannerの実行後、batch_runsとingest_jobsの状態を確認する。外部source取得の失敗はworker retryとUIで扱う。
4. 続いてhitomiのAVIFデコード問題を調査し、hitomi/cameraをそれぞれ段階移行する。

Application間の同期完了順序は保証されないため、公開routeが反映されるまでは新viewerのAPI呼び出しが失敗しうる。
両Applicationの同期完了後に受け入れ確認する。既存カタログ/S3の削除は行わない。
別媒体backupは指示どおり対象外。速度改善と本番ブラウザの署名期限切れからの復帰は引き続き未確認。
