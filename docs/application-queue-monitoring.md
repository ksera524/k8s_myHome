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

## メトリクスとアラート

- `application_queue_jobs{queue,state}`: 状態別の件数。存在しない状態も0を返す。
- `application_queue_oldest_pending_age_seconds{queue}`: 待機・処理中の最古受付からの経過秒数。自動backoffで時計をリセットしない。
- `application_queue_last_success_timestamp_seconds{queue}`: 最後の成功時刻。mediaはassetの保存時刻、api-hubはsent確定時刻、hitomiはaccepted確定時刻。実績なしは0。
- `home_camera_spool_stats_success`: 集計成功は1、失敗は0。失敗時は直近の値を保持して録画を継続するため、他のspool値は古い可能性がある。

| アラート | 条件 | 継続時間 |
|---|---|---|
| ApplicationQueueFailed | failed / uncertainが1件以上 | 5分 |
| ApplicationQueueBacklog | 通知・outboxは最古15分超、media・収集項目は最古2時間超 | 10分 |
| ApplicationQueueMetricsUnavailable | 対象キューのmetricsを取得できない | 5分 |
| CameraSpoolStatisticsUnavailable | spool集計失敗、またはメトリクス欠損 | 5分 |

キューが空の時間帯は最終成功が古くても通知しない。デプロイ時に同じDBを参照するPodが複数になっても件数を二重計上しない。

例: `sum by(queue,state) (max by(queue,state) (application_queue_jobs{namespace="sandbox"}))`で状態別件数を確認し、
`max by(queue) (application_queue_last_success_timestamp_seconds{namespace="sandbox"})`で最終成功を確認する。

## 発火時の確認

1. MetricsUnavailableはmetrics収集、NetworkPolicy、DB接続・migrationを確認する。DB障害を理由にworkerを再起動し続けない。
2. Backlogは最終成功時刻とworkerログ、DB/S3/取得元の状態を照合する。キューが減っているか、処理が止まっているかを確認する。
3. Failedはmediaの個別取得状況、通知APIまたはhitomiのnotification_statusを確認する。通知uncertainはSlackの既存配送と照合してから手動再試行する。一括再送しない。
4. CameraSpoolStatisticsUnavailableはrecorderログとspoolの読取・容量を確認する。集計成功に戻るまで、保持された容量・滞留時間を最新値として扱わない。

既存のfailed/uncertainがある場合も発火する。修正配備によって失敗行を消去したり、再送したりはしない。

## 配備順序と検証

1. api-hub、hitomi、media、cameraの修正版imageを公開する。mediaはmigration 2が必要で、既存のPreSync Jobで適用する。
2. 通知workerの終了猶予90秒とimage digestをGitOpsで反映する。新workerは終了要求後に次のclaimを始めず、処理中の1件を最大75秒で完了させる。初回の旧worker置換時は、この終了処理がまだ適用されないためsendingの有無を確認する。
3. metrics endpointが利用可能なimageに更新された後、scrape annotation・NetworkPolicy・アラートを反映する。先行してアラートのみ配備すると、旧imageのmetrics欠損が通知される。
4. 3キューのmetrics、cameraのstats_success、VictoriaMetricsの収集を確認する。空キューでも状態別0件のseriesが存在することを確認する。

回帰テストは各アプリの隔離DBテストとcameraの並行spool集計テストで実行する。
`nix develop --command automation/scripts/ci/validate.sh`にはNetworkPolicyテストと
`promtool test rules automation/tests/observability/*.test.yaml`を含む。発火待機、復旧、空キュー、欠損、複数Podの重複排除を検証する。

hitomiのacceptedは受付完了で滞留に数えない。配送failed/uncertainはapi-hubで検知する。items.failedも検知対象。cameraの不正manifestはCameraInvalidManifest、segment停止はCameraRecordingStalledで検知し、破損manifestだけのspoolも正常な空状態にしない。
