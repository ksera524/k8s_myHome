# hitomiのDB・outbox切替

## 前提

hitomi #25（merge 4db1644）のAVIFデコード修正が公開済み。
Harbor CI 40157062503は成功し、pushログのmanifest digestは
`sha256:549f071fb2f42e1e2c37da5cb06ed21ac60de13f309fd40c022743e764b2a061`。
このdigestをCronJob・migration・outboxで共通に使う。
旧CronJobのactiveは0、直近の旧Jobは失敗して終了しており、実行中の収集とは重ならない。

## 変更

- hitomi DBのPreSync migration、常駐outbox dispatcher、DBを使う収集CronJobを既存Applicationで管理する。
- 共有app role、既存application-postgresql資格情報、CA/verify-fullを使う。
- pool上限はCronJob 2、outbox 2、migration 1。所有者と資格情報の分割は追加しない。
- api-hub接続を内部ServiceのHTTPへ変更する。旧HTTPS経路のtimeoutが出ていた収集と配送を内部経路にそろえる。
- scheduleは従来どおり13:55 UTC（22:55 JST）。外部sourceを最初に見るときの既存分はbaselineであり、一斉通知しない。
- 以後の未完了項目と通知outboxはDBで追跡する。RSSから消えた未完了項目も対象となる。

## 同期後

1. migration成功、outbox Pod、CronJobのdigest・DB設定・CA mountを確認する。
2. DBのmigrationとsources/items/outboxの初期状態、app roleのTLS接続を確認する。
3. outboxログにDB接続・内部api-hub接続のエラーがないことを確認する。
4. 次の定期収集後、source別baselineと以後の項目状態、AVIF変換、outbox→api-hub→sentの状態を確認する。

検証目的のSlack実送信や本番収集Jobの手動作成は行わない。
受信先がSlackを受け付けたか不明なuncertainは自動再送しない。既存手順に沿って確認後に手動再試行する。
別媒体backupは利用者の指示どおり対象外。

## 戻す場合

先に収集CronJobを停止し、outboxを0へ変更する。実行中の収集と配送の終了を確認してから切り戻す。
DBを残し、down migrationや通知キューの削除はしない。
DB未設定の旧動作へ戻すと通知の重複判定方法が変わるため、SlackとDBの配送状態を照合する。
