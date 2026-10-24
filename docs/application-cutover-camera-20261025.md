# camera切替の準備段階

## この変更

公開済みhome-camera image（merge 32a69bc、Harbor CI 40093295503成功）を使い、既存Applicationへ次を反映する。
本番kustomizationのdigest `sha256:d5586e4c7d1e60b9e6195887f296776e7868618f83be547ec743d69cff6e9209` を維持する。

- camera DBのPreSync migration。既存app roleとapplication-postgresql Secret/CAを使う。
- 旧録画CronJobをsuspend。実行中Jobは終了まで継続する。
- 100 GiBのspool PVC、metrics用Service、recorder/uploaderを持つStatefulSet。
- StatefulSetはreplicas: 0。旧録画の終了とPVCを確認した次のPRで1へ変更する。

RTSPはbootstrap済みのhome-camera Secretを参照する。SecretのキーはRTSP_URLのみ確認し、値は出力しない。
新recorderは300秒を目安にsegmentをspoolへ保存し、uploaderがcamera DBとS3へ転送する。
spool上限80 GiB、空き2 GiB未満では停止、未送信データは自動削除しない。
NFSストレージ自体の停止を吸収する構造ではない。別媒体backupは指示どおり対象外。

## 同期後

1. migrationとApplicationの同期成功を確認する。新writerは0 replicaのまま。
2. home-camera-spoolがBoundであること、Secret・CA・NetworkPolicyを確認する。
3. 旧CronJobのactiveが0、実行中の録画Podがないことを確認する。強制削除して終了扱いにしない。
4. 別PRでStatefulSetを1へ変更し、実segment・DB/TLS・S3への転送・spool解放・metricsを確認する。
5. 再開後の録画はJST 19:00〜翌09:00。旧Job停止から新recorder稼働まで録画の空白が生じうるため、準備確認後は速やかに有効化する。

## 戻す場合

新StatefulSetを0へ変更して終了を確認後、旧CronJobを再開する。
spool、DB、S3 objectは削除しない。旧writerと新writerを重ねない。
