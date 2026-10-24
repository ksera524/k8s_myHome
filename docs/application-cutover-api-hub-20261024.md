# api-hub切替の第1段階

2026-10-24、設計・実装の5 PRがmergeされた後の確認と、最初のworkload切替。

## 反映前に確認した状態

- `registry` / `api_hub` / `hitomi` / `media` / `camera` が本番に存在し、すべて所有者は `app`。appの接続上限は80。
- sandboxの `application-postgresql` ExternalSecretはReady。対応Secretと `shared-postgresql-ca` ConfigMap、cameraのRTSP Secretが存在する。値は出力していない。
- S3 HTTPRouteはAccepted/ResolvedRefs。`https://s3.internal.qroksera.com` は証明書検証を有効にした接続でRustFSの403を返す。これは未署名要求の確認であり、署名GET・CORS・速度改善の確認ではない。
- api-hub merge commitは `5a0e08f9d2d373cd1c96c421cf7a534395be56c4`。[公開CI](https://github.com/ksera524/api-hub/actions/runs/40093269867) のHarbor digestと、Image Updaterがmainへ記録したdigestは一致した。
- 対象digestは `sha256:19294cc5ac8ca4f35f4148bd9dcb78e3569199219d32724df0d5b58b0e00edc2`。KustomizeでAPI・worker・migrationの3コンテナへ同じdigestを適用する。

## この段階の変更

`api-hub` ApplicationにPreSync migration Jobと通知workerを追加し、APIへ共用appのDB設定・CA・ブラウザ向けS3 endpointを設定する。
migrationが成功してからAPI/workerへ進む。通知producerのhitomiとmedia/cameraのwriterは後続段階で切り替える。
S3 HTTPRouteのparent/backend既定値を明示し、API serverのdefaultingによるArgoCDの差分残りを解消する。

この変更の作成時点では本番migrationと通知worker起動は未実施。mergeするとArgoCDの自動同期が実行する。
別媒体backupは利用者の指示で今回の対象外とし、切替の前提条件にはしない。既存のpgBackRest backupと復元手順は維持する。この切替PRは通常のレビュー対象として準備する。

## 同期後の確認

1. `api-hub-migration` の成功とApplicationのHealthy/Synced、APIと通知workerの起動を確認する。
2. 既存S3 proxyと署名GETをPDF/MP4で照合し、Range/Content-Range・CORSと同一条件の速度を確認する。通知の202は配送済みを意味しない。
3. API/workerの担当DB、TLS、接続数とメモリを確認する。実際の通知送信は通知先と検証内容を決めてから行う。
4. 次のmedia importに進む前に旧PDF取得Jobの終了を確認する。cameraも旧録画Job終了と新image公開を確認してから別段階で切り替える。

失敗時は新通知workerを停止して原因を確認する。DBやS3 objectの削除・down migrationは行わない。以後の手順は [本番切替手順](application-postgresql-cutover.md) を参照。
