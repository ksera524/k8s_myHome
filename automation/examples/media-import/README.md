# mediaの明示import

通常のArgoCD同期・image更新ではimportしない。このディレクトリはKustomizationから参照しない。
`--import`は既存S3 objectをカタログへ冪等に登録し、取得Jobを作らない。通常の存在・期限照合は`media-reconcile`が担当する。

初回移行・復旧時のみ、`job.yaml`を一時ファイルへコピーし、以下を確認・編集する。

- `metadata.name`: 実行ごとの一意な名前（例: `media-import-20261025-recovery`）
- `metadata.namespace`: 対象namespace（既定`sandbox`）
- `metadata.annotations`: `operations.k8s-myhome.local/reason`に実行理由を記録
- `image`: 検証済みの配布digest（`latest`は使わない）
- `PGDATABASE`と`application-postgresql`の参照: 対象DBと資格情報。新規DBを自動作成しない
- `RUSTFS_S3_BUCKET`と`WRAPPER_API_BASE_URL`: 対象bucketとAPI

```bash
cp automation/examples/media-import/job.yaml /tmp/media-import.yaml
# 上記項目を編集し、対象と理由を確認する
kubectl apply --dry-run=server -f /tmp/media-import.yaml
kubectl apply -f /tmp/media-import.yaml
kubectl -n sandbox wait --for=condition=complete job/<指定した名前> --timeout=7200s
kubectl -n sandbox logs job/<指定した名前>
```

結果の件数・key・サイズを元一覧と比較する。失敗時は原因を修正し、同じ対象へ別名のJobで再実行できる。
通常同期へのhook再追加や全件再取得を復旧手順にしない。終了後は実行結果を記録し、明示Jobを削除する。
