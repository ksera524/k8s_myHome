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
