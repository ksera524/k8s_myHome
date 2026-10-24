# アプリケーション構成見直しの実装状況

承認済みの方針は [構成レビュー](application-architecture-review-20261024.md)。既存の共用 `app` と資格情報を使い、追加アプリの提案は対象外。
アプリの実装、ローカル検証、切替用GitOpsマニフェストと運用手順を作成済み。変更は5リポジトリそれぞれのPRでレビューする。本番アプリのrolloutは行っていない。
本番への反映は、既存RTSP値からの `sandbox/home-camera` Secret作成のみ。値は出力していない。

## 実装した部分

- S3 continuation tokenをapi-hubまで渡し、繰り返しページ・トークン欠落をバッチとviewerで検出する。
- PDF/MP4の変更前測定を実施。[測定条件・結果](performance/20261024/README.md)。新S3 HTTPS Gatewayの配備後測定は未実施。
- 内部S3 HTTPSのHTTPRoute/証明書/DNS/NetworkPolicyと、viewer用CORSの宣言を追加。
- api-hubのブラウザ向け署名を `pdfs/hitomi/` のPDF/JPEGと `pdfs/videos/` のMP4に限定。900秒のGET URLを発行し、Rangeを固定しない。
- viewerの動画一斉preloadと、JPEG欠損時のPDF本体読み込みを抑制。実MP4を使ったブラウザテストで署名再発行・再生位置復元を確認。
- `api_hub` / `hitomi` / `media` / `camera` DB、既存資格情報・CAのsandbox配布、接続用NetworkPolicyを追加。app接続予算は80、全体100を維持。
- api-hub通知キュー：永続化後202、冪等受付、429待機、送信結果不明、手動再試行。S3画像のSlack共有とfile ID保存、OpenAPI更新も実装済み。
- media：planner/worker/API/import/reconcileの起動モード、安定した動画ID、試行ごとの保存キー、DBカタログ、欠損の個別再取得。PUT成功後DB更新前の停止からの回復テストを実施。
- viewerにカタログ画面、状態・未読絞り込み、再取得・取得状況表示を追加。従来画面と切替可能。
- hitomi：初回baseline、項目claim、NG判定の保存、画像S3保存と通知outbox、漫画の更新期間を含めた重複排除。隔離DBでbaseline・再送・古いclaimの拒否を確認。
- camera：常駐segment録画、PVC上のmanifest、別uploader、DB障害時も録画できる構造、spool容量制御・監視値・アラートを実装済み。
- migration/workerを含むCI、[切替用マニフェスト](../automation/examples/application-architecture/)、[移行と切戻し手順](application-postgresql-cutover.md)を追加。plannerは停止状態、cameraは0 replicaで準備し、旧writerとの重複を防ぐ。

## 検証結果

| 対象 | 確認結果 |
|---|---|
| api-hub | 通常テスト34件、隔離DBの冪等受付・同時claim・429・lease回復・手動再試行。画像共有成功と結果不明をmockで再現しfile IDを確認 |
| hitomi | lib 56件、HTTP 3件。隔離DBでbaseline、RSSから消えた項目、outbox再送、配送状態照合、古いclaimの拒否を確認 |
| media | 通常テスト24件、隔離DBで安定ID、preview個別修復、PUT後DB更新前の回復、checksum、直接配信とproxy切戻しを確認 |
| camera | 通常テスト18件。追加で隔離DB/S3停止時の復旧と、実FFmpegによる未送信segmentを残したままの継続録画を確認 |
| viewer | APIテスト7件、production build、実MP4 fixtureのRange応答・署名再発行・再生位置復元、カタログ操作、PDF本体の不要な取得抑制を確認 |
| コンテナ | API/batch/viewer/hitomi/cameraの5 imageをローカルビルド。4アプリのimage内migrationが専用DBで成功（API 2件、他各1件）。batch/viewerのsmoke test成功 |
| Kubernetes/CI | 全体validate、DB権限・接続許可のテスト、NetworkPolicy、manifest整合性、alert test、4つの変更workflowのactionlintが成功。切替用例もYAML/schema検証済み |

Slackへの実送信は行っていない。ブラウザ検証のメディアは生成したfixtureであり、本番の私的メディアを使っていない。
ローカルimageタグは `architecture-20261024`。Harborへはまだ公開しておらず、registry digestは未確定。

## 本番切替時に残る作業

- 各アプリPRをmergeし、5 imageをHarborへ公開してdigestを固定する。切替用例を既存ArgoCD sourceへ反映し、手順に沿って基盤同期、migration、import、旧writer停止、新writer起動を行う。
- 新S3 HTTPS経路の配備後、実端末からPDF/動画取得・シーク・CORS・署名期限切れを確認し、同一条件で再測定する。現在の結果から新経路の改善率は断定しない。
- 別媒体backupは保存先が未確定。現NFS内のbackupだけで独立backupができたとは扱わず、保存先決定後に独立した復元先でrestore testを行う。

## 検証用リソース

本番計測用Pod/NetworkPolicyは削除済み。隔離PostgreSQL（`/tmp/api-hub-pgtest.V5VpRX/data`、127.0.0.1:15433）とviewer検証サーバー（127.0.0.1:5174）は検証後に停止した。
ローカルDBのデータと検証用imageは残している。本番DBへのmigrationは未実施。
