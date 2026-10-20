# 共通 PostgreSQL の運用

正本は `manifests/platform/shared-postgresql/`。PGO 6.0.3 が PostgreSQL 18 と
pgBackRest を管理する。Namespace は `database`、クラスタ名は `shared-postgresql`。
移行の実施結果は [移行計画](../tasks/shared-postgresql.md) に記録する。

## 接続と資格情報

- primary: `shared-postgresql-primary.database.svc:5432`
- Harbor: DB `registry`。Harbor と他アプリは共用ログインロール `app` を使う。
  DB / schema はアプリの要件に合わせて追加し、共用ロールに所有権を与える。
- パスワードの正本は Pulumi ESC の `postgresql.admin_password` と `postgresql.password`。
  ESO は入力 Secret `database/postgresql-input`、`harbor/harbor-database-secret`、
  `observability/grafana-postgresql` に配布する。
- `postgresql-credentials` CronJob は 2 分ごとに入力と PGO の Secret を比較する。
  変更時だけ password と verifier を更新し、TLS 検証付き SQL 接続で反映を確認する。
  PGO の Secret を ESO の所有物に変更しない。
- PGO の公開 CA だけを Harbor / observability の `shared-postgresql-ca` に配布する。
  管理パスワードと TLS 秘密鍵は Harbor に配布しない。
- ローテーションは共用ユーザーを利用する全アプリを停止してから ESC 更新、ESO 同期、資格情報 Job 成功を確認し再開する。
  単一ロールの新旧パスワードが同時に使えるとは扱わない。
- 2026-10-19 に旧 `harbor` ロールから `app` へ所有権と復元マーカーの参照権限を移し、旧ロールを削除した。
  `postgresql.harbor_password` は廃止済み。パスワード値そのものは引き継いでいる。

## ローカル PC から psql で接続する

この PC では Nix のユーザープロファイルに psql 18.6 をインストールし、
`registry` / `app` への TLS 1.3 接続と既存データの読み取りを確認済み。
クラスタへ接続できる `kubectl` と、Pulumi ESC の `postgresql.password` を使用する。

### 初回設定

Nix が導入されている PC では次でクライアントをインストールする。

```sh
nix profile install 'nixpkgs#postgresql_18'
psql --version
```

公開 CA を保存する。CA が更新された場合も、この取得操作を再実行する。

```sh
mkdir -p "$HOME/.postgresql"
chmod 700 "$HOME/.postgresql"
kubectl -n harbor get configmap shared-postgresql-ca \
  -o jsonpath='{.data.ca\.crt}' > "$HOME/.postgresql/shared-postgresql-ca.crt"
chmod 600 "$HOME/.postgresql/shared-postgresql-ca.crt"
```

次を `~/.pg_service.conf` に初回のみ追記する。この PC では設定済み。
既存の `[shared-postgresql]` がある場合は、その設定を使うか同じセクションを編集し、重複追加しない。
パスワードは設定ファイルに保存せず、接続時に入力する。

```sh
cat >> "$HOME/.pg_service.conf" <<EOF

[shared-postgresql]
host=shared-postgresql-primary.database.svc
hostaddr=127.0.0.1
port=15432
dbname=registry
user=app
sslmode=verify-full
sslrootcert=$HOME/.postgresql/shared-postgresql-ca.crt
connect_timeout=10
EOF
chmod 600 "$HOME/.pg_service.conf"
```

`hostaddr` はポート転送先、`host` は証明書の検証に使う Service DNS 名。
`host=localhost` への変更や証明書検証の無効化は不要。

### 接続するたびに行う操作

ターミナル1で現在の primary Pod を選び、ローカルの 15432 番ポートへ転送する。
primary Service は selector を持たないため、`port-forward svc/...` ではなく Pod を指定する。

```sh
postgresql_primary_pod="$(kubectl -n database get pods \
  -l 'postgres-operator.crunchydata.com/cluster=shared-postgresql,postgres-operator.crunchydata.com/role=master' \
  -o jsonpath='{.items[0].metadata.name}')"
kubectl -n database port-forward "pod/$postgresql_primary_pod" 15432:5432 --address 127.0.0.1
```

転送を動かしたまま、ターミナル2で接続する。パスワードには Pulumi ESC の
`postgresql.password` を入力する。

```sh
psql service=shared-postgresql -W
```

接続後の確認例:

```sql
SELECT current_database(), current_user;
SELECT ssl, version FROM pg_stat_ssl WHERE pid = pg_backend_pid();
```

終了は psql で `\q`、ポート転送のターミナルで `Ctrl-C`。
Pod の再起動や primary の変更で転送が切れた場合は、primary の選択からやり直す。

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
   共用ユーザーへの切り替え前のバックアップは `harbor` 所有のため、`app` への所有権移管と
   `platform_bootstrap` の USAGE / `migration` の SELECT 付与を管理接続で行ってから起動する。
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
各 1 Pod、rolling update 時に各 2 Pod として計 40 接続を見込み、共用 app ロールの合計上限を 50、
DB 全体を 100 とする。exporter は無効。exporter を追加する場合も CA と接続予算を追加する。
他アプリは DB / schema と ESO 定義 / CA 配布 / NetworkPolicy の許可を追加する。
ESO は同じ `postgresql.password` を参照し、ロールと ESC パスワードは追加しない。
共用ユーザーは各アプリのデータにアクセスできる構成とする。

PUBLIC の CONNECT / TEMP を取り消して共用 app に必要な権限を与え、管理接続分を残した接続予算を設定する。

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

## Grafana から SQL を実行する

[PostgreSQL / SQL ダッシュボード](https://grafana.internal.qroksera.com/d/home-lab-postgresql) を開く。
接続・TLS 情報、DB 容量、接続数、テーブル容量・推定行数、実行中 SQL を表示する。
これらは現在の DB 統計を SQL で取得するもので、過去の監視メトリクスの蓄積ではない。

上部の「SQL を実行する（Explore）」から **Code** モードで SQL を編集し、**Run query** で実行する。
データソースは `PostgreSQL / registry`、接続ユーザーは共用の `app`。例:

```sql
SELECT current_database(), current_user, now();
SELECT repository_id, count(*) FROM artifact GROUP BY repository_id LIMIT 20;
```

Grafana も ESC `postgresql.password` を ESO で受け取り、PGO の公開 CA で `verify-full` 接続する。
資格情報 Job が公開 CA を Harbor と observability に配布し、変更時は reloader が Grafana を再起動する。
Grafana の接続上限は 5、idle は 1。Harbor の rolling update 時 40 と合わせて 45 接続を見込む。
共用 app の上限 50 に収まるよう、他アプリ追加時には全体の接続予算を再調整する。

他 DB を追加する場合は、その DB 名を指定したデータソースを Git に追加し、Explore で選択する。
同じ `app` と ESC キーを使い、DB の所有権・接続権限も設定する。
ダッシュボードは GitOps 管理のため、定型 SQL の変更は
`manifests/platform/observability/config/postgresql-dashboard.json` に反映する。
SQL 編集の使い方は [Grafana PostgreSQL query editor](https://grafana.com/docs/grafana/latest/datasources/postgres/query-editor/) を参照。

## バージョン更新

PGO chart を起点にした一括更新と、整合性・更新・バックアップ・復元の CI は
[PostgreSQL の更新と CI](postgresql-updates.md) を参照。
