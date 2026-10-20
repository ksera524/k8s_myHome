# PostgreSQL の更新と検証

[PGO Kustomization](../manifests/platform/pgo/kustomization.yaml) の chart version を起点に、
その chart が指定する PostgreSQL / pgBackRest と補助コンテナのイメージを揃えます。
現在の `spec.postgresVersion` を維持し、独立した最新タグを各所へ設定しません。

## 自動更新

[Renovate workflow](../.github/workflows/renovate.yml) は PGO chart の PR 作成後、
[sync-renovate-postgresql.py](../automation/scripts/ci/sync-renovate-postgresql.py) を実行します。
同一 repo の `github-actions[bot]` 作成 `renovate/` PR で、PGO Kustomization に変更があるものが対象です。

信頼済み同期処理が候補を worktree に展開し、chart を取得して関連ファイルを更新します。
PR 側のコードや Git hooks を実行せず、通常 push で同時更新の上書きを拒否します。
その後、最新 HEAD の検証 workflow を dispatch します。

PGO は OCI の公開日時がない場合も候補を作る設定なので、3 日待機が保証されない場合があります。
major chart 更新には Dashboard 承認が必要です。DB major の変更はこの自動更新経路に含めません。

## 手動変更と整合性

[postgresql-versions.py](../automation/scripts/ci/postgresql-versions.py) は chart metadata、Operator、DB major、
DB / pgBackRest / 資格情報 Job / Harbor 待機コンテナ / 復元例のイメージを照合します。

```bash
nix develop --command python3 automation/scripts/ci/postgresql-versions.py
# chart version を編集した後、取得・同梱・関連イメージ同期を行う
nix develop --command python3 automation/scripts/ci/postgresql-versions.py --sync
nix develop --command automation/scripts/ci/validate.sh
```

`--sync` は作業ツリーを変更し、検証成功後に古い同梱 chart を削除します。
更新先 chart が現在の DB major を提供しなければ失敗させ、自動 major 切り替えは行いません。

## 実行テスト

[ci-deploy-validate.yml](../.github/workflows/ci-deploy-validate.yml) の `postgresql-runtime` は、
workflow に列挙された PostgreSQL 関連ファイルの変更時、または手動 input `postgresql_runtime=true` の場合に実行します。
全 DB 関連設定を自動検出するわけではないため、変更検出の path も確認します。

[postgresql-runtime.py](../automation/scripts/ci/postgresql-runtime.py) は一時 kind クラスタで次を確認します。

1. base ref の Operator / DB / pgBackRest を起動し、検証データを作成。
2. 更新候補を適用し、DB Pod の再起動後に実行 image と readiness を確認。
3. app / verify-full の接続、major、データ件数・内容、読み書きを確認。
4. 更新後 full backup の成功 ID を確認し、別 PostgresCluster に復元して同じ検証を実行。
5. 診断情報を保存して一時クラスタを削除。

同版比較でも再起動・backup・restore を実行します。既存の kubeconfig は使わず、専用の一時パスを指定します。
Docker が使える環境での実行例:

```bash
nix develop --command python3 automation/scripts/ci/postgresql-runtime.py \
  --base-ref origin/main --logs /tmp/postgresql-runtime-logs
```

CI の上限は 30 分、diagnostics artifact は 7 日保持です。
このテストは本番 NFS / ESC / ESO / Harbor 全体、PITR、major 移行、旧 backup の新環境復元、
全クラスタ喪失からの再構築を検証しません。[運用上の復元確認](shared-postgresql.md) は別に行います。
