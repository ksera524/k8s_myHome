# 業務キューと録画の監視

PodのReadyと業務の完了を別々に監視する。既存VictoriaMetricsのannotated Pod discoveryで30秒ごとに集計し、vmalert/Alertmanagerの既存通知経路を使う。

| 対象 | metricsの取得先 | queueラベル | 待機状態 |
|---|---|---|---|
| Slack配送 | api-hub:3000/metrics | notifications | pending / sending / retry |
| 通知受付 | hitomi-outbox:9090/metrics | hitomi_outbox | pending / verify（移行時一度の照合） |
| 収集項目処理 | hitomi-outbox:9090/metrics | hitomi_items | pending / running / retry |
| メディア取得 | media-api:3000/metrics | media | pending / running / retry |

全endpointは既存のDB poolを共有するため接続上限は増やさない。DB読み取りは3秒で打ち切り、失敗時は503。取得失敗を空キューとして報告しない。
NetworkPolicyはobservabilityのVictoriaMetricsから対象portへの接続を許可する。
通知本文・保存キー・URL・IDはmetricsやalertのラベルに含めない。

## キュー確認の待機

api-hub の通知task、hitomi の outbox、media worker は、処理開始時にまず確認する。
空キュー・DB接続エラー等では待機を1→2→4→8→16→30秒へ延ばし、1件処理すると1秒へ戻す。
行ごとの再試行日時・lease・heartbeat・通知の冪等性は従来のまま維持する。
待機中に新着や再試行期限が到来した場合、次の確認まで最大約30秒かかる（DB・外部処理時間は別）。
hitomi outbox から api-hub 配送までの2段階では、両方が空なら待機が合計約60秒になる場合がある。

長時間空の状態でのキュー確認は、各workerで約86400回/日から約2880回/日へ減る計算。
これは確認ループ回数の見積りで、SQL総数・実測CPUの削減率ではない。
監視の30秒scrapeと毎時media reconcile、収集CronJobの頻度は変更しない。

## メトリクスとアラート

- `application_queue_jobs{queue,state}`: 状態別の件数。存在しない状態も0を返す。
- `application_queue_oldest_pending_age_seconds{queue}`: 待機・処理中の最古受付からの経過秒数。自動backoffで時計をリセットしない。
- `application_queue_last_success_timestamp_seconds{queue}`: 最後の成功時刻。mediaはassetの保存時刻、api-hubはsent確定時刻、hitomiはaccepted確定時刻。実績なしは0。
- `home_camera_spool_stats_success`: 集計成功は1、失敗は0。失敗時は直近の値を保持して録画を継続するため、他のspool値は古い可能性がある。

| アラート | 条件 | 継続時間 |
|---|---|---|
| ApplicationQueueFailed | 通知系のfailed / uncertainが1件以上。旧exporterも従来どおり検知 | 5分 |
| ApplicationUnreviewedFailure | hitomi_items / hitomi_sources / mediaの未確認失敗が1件以上 | 5分 |
| ApplicationQueueBacklog | 通知・outboxは最古15分超、media・収集項目は最古2時間超 | 10分 |
| ApplicationQueueMetricsUnavailable | 対象キューのmetricsを取得できない | 5分 |
| CameraSpoolStatisticsUnavailable | spool集計失敗、またはメトリクス欠損 | 5分 |
| CameraRecordingStalled | 録画可能な時間帯に正常確定segmentがsegment長の2倍+60秒を超えて途絶 | 2分 |

cameraの録画監視は再接続で猶予をリセットしない。`home_camera_recording_active`が一時的に1でも、正常確定segmentがなければ`home_camera_recording_stalled`が1になる。正常確定で解除し、時間帯外・容量停止中は監視の猶予を解除する。FFmpegごとの再接続判定は独立しており、録画停止の通知中も接続回復を試みる。

キューが空の時間帯は最終成功が古くても通知しない。デプロイ時に同じDBを参照するPodが複数になっても件数を二重計上しない。

例: `sum by(queue,state) (max by(queue,state) (application_queue_jobs{namespace="sandbox"}))`で状態別件数を確認し、
`max by(queue) (application_queue_last_success_timestamp_seconds{namespace="sandbox"})`で最終成功を確認する。

## 発火時の確認

1. MetricsUnavailableはmetrics収集、NetworkPolicy、DB接続・migrationを確認する。DB障害を理由にworkerを再起動し続けない。
2. Backlogは最終成功時刻とworkerログ、DB/S3/取得元の状態を照合する。キューが減っているか、処理が止まっているかを確認する。
3. UnreviewedFailureはhitomi管理CLIまたはmedia画面の「失敗の管理」で原因と履歴を確認する。確認済みは警告を解除するが自動再試行を継続し、対象外は理由付きで取得を停止する。原因変更・明示再実行後の失敗は再び未確認になる。
4. Failedは通知APIまたはhitomiのnotification_statusを確認する。通知uncertainはSlackの既存配送と照合してから手動再試行する。一括再送しない。
5. CameraSpoolStatisticsUnavailableはrecorderログとspoolの読取・容量を確認する。集計成功に戻るまで、保持された容量・滞留時間を最新値として扱わない。

通知系の既存failed/uncertainは引き続き発火する。取得系は未確認だけを継続警告し、確認済み・対象外の履歴も保持する。修正配備だけで成功扱いや再送は行わない。

## 配備順序と検証

1. api-hub、hitomi、media、cameraの修正版imageを公開する。mediaはmigration 2が必要で、既存のPreSync Jobで適用する。
2. api-hubは統合API/通知taskを1 replica/Recreate、終了猶予90秒で動かす。終了要求後は新claimを始めず、進行中の1件を最大75秒で確定し、HTTPのdrain後に共有poolを閉じる。
3. metrics endpointが利用可能なimageに更新された後、scrape annotation・NetworkPolicy・アラートを反映する。先行してアラートのみ配備すると、旧imageのmetrics欠損が通知される。
4. 4キューのmetrics、cameraのstats_success、VictoriaMetricsの収集を確認する。空キューでも状態別0件のseriesが存在することを確認する。

回帰テストは各アプリの隔離DBテストとcameraの並行spool集計テストで実行する。
`nix develop --command automation/scripts/ci/validate.sh`にはNetworkPolicyテストと
`promtool test rules automation/tests/observability/*.test.yaml`を含む。発火待機、復旧、空キュー、欠損、複数Podの重複排除を検証する。

hitomiのacceptedは受付完了で滞留に数えない。配送failed/uncertainはapi-hubで検知する。items.failedも検知対象。cameraの不正manifestはCameraInvalidManifest、segment停止はCameraRecordingStalledで検知し、破損manifestだけのspoolも正常な空状態にしない。


## 取得失敗の確認状態

`application_failure_records{queue,disposition}`は未解決の失敗をunreviewed / acknowledged / excludedに分ける。hitomi_sourcesはRSS取得・漫画確認の失敗で、item IDを持たない。任意のURL・原因文字列はラベルにしない。
`application_queue_oldest_unreviewed_pending_age_seconds`を取得系の滞留警告に使用し、確認済みの古いretryを継続警告から外す。元の待機時間とfailed件数は観測用として保持する。新しいpendingと未確認のretryは引き続き滞留を検知する。

アプリのmigration 3と新exporterを適用後、監視ルールを切り替える。新指標がない旧exporterには従来指標へフォールバックする。確認後の再発には5分の継続時間を改めて適用する。複数Podの値はmaxで集計する。

mediaの24時間整理でも失敗履歴と確認状態は残る。hitomiの直接デバッグ通知はログへ集約し、取得失敗の警告と重複させない。収集Jobのfailed operationsと終了結果は実際の失敗を保つ。
