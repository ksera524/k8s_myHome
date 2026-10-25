# 簡素化の実行記録

2026-10-25 JST。基準HEAD: api-hub `14f3e5b`、hitomi `5b5949c`、media `8ee1e4d`、camera `e9fffee`、GitOps `f2421ec`。全対象の作業treeは開始時clean。

## P0: 切替前

19:20〜19:23 JSTにread-onlyで確認。ArgoCDの全ApplicationはSynced/Healthy。

| 対象 | 実Podのimage digest | 実処理の状態 |
|---|---|---|
| api-hub API/worker | `sha256:da6986ab1aab6903feca8d49f19edcd2a4d9e8cd6e60921824578032538d9871` | notificationsは0件。配送成功の証拠とはしない |
| hitomi outbox | `sha256:afa8a3b592cc64fc26a623a39d54edfe3d3e724cea6150cb9a908169da52c005` | sources/items/notification_outboxは0件、初回baseline前 |
| media API/worker | `sha256:b5de462ed830998a79d4dedb95b82df1adb2868d64c569278474b888a06572c2` | PDF/preview各ready 1459・expired 50、video ready 336・failed 3 |
| camera recorder/uploader | `sha256:1ecc1586e2a56fac3c8efac8786ff88f63597ed9927c678eb94ce1a4fd3bfdb0` | recordings 0件、spoolはlock/空sessionだけ。DBだけに残る未完了行なし |

cameraは録画時間帯にもかかわらず、spool bytes 0、recording_active 0、recorder_restarts_total 122。実録画は未成功。既知のRTSP引数不備の修正と人工RTSP試験をP2で扱う。時間帯外の正常待機とは分類しない。
hitomiは22:55 JSTの日次schedule。既存のsources/items/outboxを初期化せず継承する。
通知本文・資格情報は取得記録へ含めていない。DBの確認は件数・状態のSELECTのみでfixtureを投入していない。

## P1

通常media manifestと旧切替exampleからmedia-import hookを除去。生成器もhookを生成しない。
明示Jobと対象・digest・理由を指定する[手順](../automation/examples/media-import/README.md)を追加。
過去の切替記録のPostSync成功は履歴として保持する。

以降の変更・検証結果は段階ごとに追記する。配備していない変更を配備済みとは記録しない。

検証: `nix develop --command automation/scripts/ci/validate.sh`成功。mediaの`cargo test --locked`は24件成功、隔離PostgreSQLで`durable_media_recovery`成功（import 2回の冪等性と取得Job非生成を含む）。

## P2: camera

完成mp4と既存キーのmanifestを正本にし、uploader.lockの排他で再送。SQL claim/lease/heartbeat、sqlx依存、CIのPostgreSQLを撤去。旧manifestは追加フィールド省略を許容。失敗回数と次回試行をatomic renameで保存し、1件失敗しても走査を継続する。

S3 HEADは404だけPUTへ進み、認証・一時障害・サイズ不一致を失敗として保持。ローカルchecksum確認を維持し、S3キー/サイズの照合後に動画→manifestの順で削除する。動画だけ消失したmanifestはS3を照合し、両方欠損は保持する。破損manifestは再生成せず保持し、専用件数とアラートで検知する。

RTSPは`-timeout`で接続を制限し、完成segmentがsegment長の2倍+起動猶予60秒停止すると再接続する。DBなし回復試験は7件成功（FFmpeg 7.1.1、実segment継続、RTSP無応答と再接続を含む）。

配備順序: 先に互換imageの回復試験を通す。旧設定の`--record`/`--upload`で起動でき、旧migration Job向け`--migrate`はDBを変更せず終了する暫定互換（P6で削除）。その後GitOpsからPG設定/CA/DBラベル/migrationを除去し、StatefulSetの順序付き更新で旧uploader終了後に新uploaderを起動する。強制削除しない。PVC/S3の移動・削除を行わない。

切戻し: 旧digestとPG設定を同時に戻す。writer/uploaderの終了を確認して交代し、S3保存済みと旧DBの履歴差分を明示する。camera DBの物理削除は行わない。

## 2026-10-26 再開時の確認

P1: media #3、GitOps #117をマージし配備済み。ArgoCDのhitomi-pdf同期対象にimport Jobなし。P2アプリhome-camera #7をマージ、公開CI成功、新digest `sha256:106847f78175cc4e478c471ba71704eefe284604a30b228b0faf1e3c51ce101c`が配備済み。07:24 JST、S3の2026/10/25 UTC prefixに146 object/1,671,012,127 bytes。spoolは現在のpart/active/CSV/locksだけで、完成分は解放済み。recording_active=1、invalid_manifests=0、stalled=0、partial=0、stats_success=1。GitOps #118も全CI成功後マージ。PG設定除去の反映と09:00 JSTの時間帯終了確認は追跡する。

hitomiの日次Jobはsources 11（initialized）、baseline 852件を保存し、outboxとapi-hub通知は0件。123hon 1件とcomic-walker 2件のRSS取得timeoutにより3 failed operationsで終了。初回全経路の成功とはしない。既存履歴を維持して次の収集へ引き継ぐ。

## P3

通知受付をoutbox accepted/items notification_acceptedで終端にする。追加migration 2で既存行を分類し、api_id付き非sent行をverifyで一度照合。不一致等はreceipt_failedとして保持。有効な202まで同じpayloadを再送し、配送結果の継続GETは撤去する。

同一feed6回・章revision更新・再掲載・baseline維持、応答喪失/503/429/ID欠落202からの同一payload再送、400/409、移行照合のidentity不一致、受付後の非GET、切戻しSQLを隔離DBで確認。回復試験3件成功。通常lib試験58件成功。

先にアプリimage/migrationを配備し、api-hubの配送失敗監視が有効な状態で受付責任を切り替える。その後、GitOpsのscheduleをJST 02:55/06:55/10:55/14:55/18:55/22:55に変更する。負荷時はscheduleだけ日次へ戻し、履歴を残す。切戻しはhitomi/docs/state.mdとrollback-acceptance.sqlに従い、未知migrationのある旧imageへhookをそのまま戻さない。
