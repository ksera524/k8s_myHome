# 共通 PostgreSQL の運用

正本は `manifests/platform/shared-postgresql/`。PGO 6.0.3 が PostgreSQL 18 と
pgBackRest を管理する。Namespace は `database`、クラスタ名は `shared-postgresql`。
移行の実施結果は [移行計画](../tasks/shared-postgresql.md) に記録する。

## 接続と資格情報

- primary: `shared-postgresql-primary.database.svc:5432`
- Harbor: DB `registry`、ロール `harbor`。他アプリは別 DB・別ロールを追加する。
- パスワードの正本は Pulumi ESC の `postgresql.admin_password` と `postgresql.harbor_password`。
  ESO は入力 Secret `database/postgresql-input` と `harbor/harbor-database-secret` に配布する。
- `postgresql-credentials` CronJob は 2 分ごとに入力と PGO の Secret を比較する。
  変更時だけ password と verifier を更新し、TLS 検証付き SQL 接続で反映を確認する。
  PGO の Secret を ESO の所有物に変更しない。
- PGO の公開 CA だけを `harbor/shared-postgresql-ca` に配布する。
  管理パスワードと TLS 秘密鍵は Harbor に配布しない。
- ローテーションは Harbor を停止してから ESC 更新、ESO 同期、資格情報 Job 成功を確認し再開する。
  単一ロールの新旧パスワードが同時に使えるとは扱わない。

## バックアップ

データ PVC は 10Gi、pgBackRest repo1 は 20Gi を要求し、`nfs-postgresql` の `Retain` を使う。
いずれもホスト `192.168.10.11` の外付け SSD、`/mnt/k8s-storage/nfs-share` 上にある。
NFS の要求容量はディスク上限・予約を保証しない。同一 SSD / NFS の喪失では両方が失われる。

full は日曜 18:00 UTC（月曜 03:00 JST）、differential は月〜土曜 18:00 UTC。
full は 3 世代を保持し、WAL も保管する。手動 full backup は次で開始する。

```sh
kubectl -n database annotate postgrescluster shared-postgresql --overwrite \
  postgres-operator.crunchydata.com/pgbackrest-backup="$(date -u +%Y%m%dT%H%M%SZ)"
kubectl -n database get jobs,pods
kubectl -n database exec shared-postgresql-repo-host-0 -c pgbackrest -- \
  pgbackrest --stanza=db info
```

Job Complete と `pgbackrest info` の最新成功時刻を両方確認する。
資格情報 Job の成功だけではバックアップ成功を意味しない。

## 再起動と再構築

既存 PVC を保持した Pod / VM の再起動では PGO が既存データを起動する。
VM の CPU は `host-model` とする。QEMU 既定 CPU は UBI 9 の x86-64-v2 要件を満たさず、
このホストでの `host-passthrough` は libc segfault を観測したため使用しない。

クラスタ自体を再作成する場合、NFS ファイルが残っていても Kubernetes の PV / PVC 定義は失われる。
動的プロビジョナが作った空ディレクトリを旧データと取り違えない。

1. NFS、DNS、ESO、PGO を復旧する。ESC bootstrap 用トークンも別途必要。
2. 旧 DB / repo の NFS パスとバックアップを確認し、旧プロセスが停止したことを確認する。
3. 復旧作業中は Harbor を停止し、ArgoCD が復旧用設定を戻さないよう Git に設定を反映する。
   `shared-postgresql` を無条件に空の PVC で立ち上げない。
4. 保持した repo を静的 PV / PVC として再接続するか、保管した論理 dump を別 DB に復元する。
   pgBackRest の場合は固定版 PGO の restore 設定と対象 backup を指定し、復元 Job 完了を待つ。
   同じ repo を別の空クラスタのバックアップ先として初期化しない。
5. ESC の資格情報を再反映し、実際のアプリ資格情報・`verify-full` で接続する。
   テーブル・行数・シーケンス・復元世代を確認してから Harbor を再開する。

旧 PGDATA と repo が健全で、元の PVC 名で静的 PV に再接続できた場合、固定版 CRD の
`spec.dataSource.volumes` は既存ボリュームの再利用を指定できる。例は次のとおり。
実際の PVC 名と NFS パスを inventory で照合し、DB を起動する前に Git の復旧用設定へ加える。
この再構築経路の実機演習は未実施。

```yaml
spec:
  dataSource:
    volumes:
      pgDataVolume:
        pvcName: shared-postgresql-main-9lm4-pgdata
      pgBackRestVolume:
        pvcName: shared-postgresql-repo1
```

PVC の `volumeName` と PV の NFS server / path を明示し、動的作成を避ける。
旧クラスタの UID / resourceVersion / claimRef.uid は新クラスタへそのまま再適用しない。
PGDATA が破損している場合はこの再利用経路を使わず、バックアップから別領域へ復元する。

Harbor core / jobservice の起動ゲートは、DB が接続可能なだけでは通過させず、
`platform_bootstrap.migration` の確認済み世代を要求する。
空 DB や復元前の DB にマーカーを自動作成しない。
バックアップの復元には人による対象選択・検証が必要であり、全クラスタ喪失からの無操作復旧は保証しない。

[PGO の復元・クローン手順](https://access.crunchydata.com/documentation/postgres-operator/latest/tutorials/backups-disaster-recovery/disaster-recovery)
を参照する。稼働中の本番クラスタに in-place restore を試さない。

## 切り戻し

旧 Harbor PVC `harbor/database-data-harbor-database-0` は保持する。
移行前 dump は NFS の `harbor-pgo-migration-20261019/` に保管する。
切り替え後に新 DB への書き込みを再開した場合、旧 PVC に戻すだけでは新しいデータが失われる。
必ず書き込みを停止し、新 DB の最新 dump と旧環境の互換性を確認して戻すか、新 DB を修復する。

## 接続数とアプリ追加

Harbor core / jobservice は各 Pod の maxOpenConns 10 / maxIdleConns 3。
各 1 Pod、rolling update 時に各 2 Pod として計 40 接続を見込み、Harbor ロールの上限を 50、
DB 全体を 100 とする。exporter は無効。exporter を追加する場合も CA と接続予算を追加する。
他アプリは専用 DB / ロール / ESC パスワード / ESO 定義 / NetworkPolicy の許可を追加し、
PUBLIC の CONNECT / TEMP を取り消して、管理接続分を残した接続予算を設定する。

## 検証範囲

2026-10-19 に論理 dump の復元と、pgBackRest から独立クローンへの復元を実行した。
public の 49 テーブルの件数・内容ハッシュと 47 シーケンスを比較した。
TLS、誤パスワード拒否、別 DB への接続拒否、復元マーカーなしの待機と確認後の通過も実測した。
クローン定義は `automation/examples/postgresql/restore-test.yaml` に残し、通常の GitOps 対象からは除外する。
全クラスタを破棄する再構築演習、時刻指定 PITR、運用中のパスワードローテーション演習は未実施。

移行前後の PV / NFS パスはバックアップディレクトリの `pv-inventory.json` に保存している。
旧 Harbor PVC は Bound、旧・新 DB と repo の PV reclaim policy は Retain と確認した。
control-plane VM の永続 CPU 定義も host-model に変更済みだが、稼働中 CPU の反映は次回コールド起動時となる。

Harbor の最終機能試験では管理者 API 認証、既存イメージ pull、一時リポジトリへの push、
Trivy scan Success、テストリポジトリ削除まで成功した。未許可 Pod の TCP 接続拒否も確認済み。
