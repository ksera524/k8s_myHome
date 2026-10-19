# 共通 PostgreSQL 基盤と Harbor DB 移行計画

作成日: 2026-10-18。採用方式: **PGO（Crunchy Postgres Operator）**。状態: **本番移行完了（追加の復旧演習は残項目）**。
以下は当初計画を含む。実装済み構成・復旧手順の正本は [運用手順](../docs/shared-postgresql.md)、実測結果は末尾の移行実施記録を参照。

## 目的と範囲

Harbor 内蔵 PostgreSQL のデータを、独立して GitOps 管理する共通 PostgreSQL に移す。
Harbor と他アプリは同じ PostgreSQL サーバーの共用ロール `app`・共通パスワードを使う。
永続データは外部ストレージに置く。Redis、Registry、Trivy、Jobservice のストレージは変更しない。
初期段階では HA、PgBouncer、既存の他アプリ DB の一括移行、PostgreSQL のメジャー更新を含めない。

## 調査済みの現状

- Harbor の正本: `manifests/platform/harbor/values.yaml`、chart `1.19.4`。
- Application: `manifests/bootstrap/applications/platform/harbor.yaml`、wave 10、自動同期・prune・selfHeal 有効。
- `database.type: internal`、`redis.type: internal`。永続 PVC はすべて `nfs-external`。
- DB PVC: `harbor/database-data-harbor-database-0`、要求 1Gi。
- NFS: `192.168.122.1:/mnt/k8s-storage/nfs-share`。外付け SSD `/dev/sda1`（ext4、USB H/W RAID1）上。DB とバックアップは同じ媒体。
- 読み取り専用 SQL で確認した稼働 DB: PostgreSQL **18.6**、DB `registry` 約 **13 MB**、拡張 `plpgsql 1.0`。
  これは移行時間や将来の容量を保証する値ではなく、実装前に再測定する。
- chart の `database.external` は host / port / username / coreDatabase / existingSecret / sslmode を提供。
  Secret のキーは `password`。接続プールの既定は `maxOpenConns: 900`、`maxIdleConns: 100`（Pod ごと）。
- Secret は Pulumi ESC → ESO。`config-secrets` は wave 9。
- `platform` AppProject は `database` Namespace を許可済み。
- NetworkPolicy 実行基盤は Flannel + kube-network-policies。fail-open の制約あり。

## 採用する初期構成

| 項目 | 計画 |
|---|---|
| owner | Operator 用 `pgo` と DB 用 `shared-postgresql` を別 Application とし、project `platform` で管理 |
| 配置 | Operator は Namespace `postgres-operator`、DB は `database` の PostgresCluster `shared-postgresql`、instance replicas 1 |
| 接続 | PGO の primary 用 ClusterIP Service（想定 `shared-postgresql-primary.database.svc:5432`、固定版で確認） |
| イメージ | PGO 対応の Crunchy PostgreSQL 18 イメージ。Operator / PostgreSQL / pgBackRest の互換組合せ・patch・digest を固定 |
| ストレージ | 新規専用 PVC、`nfs-postgresql`、初期要求 10Gi。旧 Harbor PVC は流用しない |
| リソース初期案 | requests CPU 250m / memory 512Mi、limits CPU 1 / memory 1Gi |
| DB 初期案 | `max_connections=100`、管理・バックアップ用の余裕を確保 |
| Harbor | DB 名 `registry`、共用ログインロール `app`、内部 Redis を継続 |
| 公開範囲 | クラスタ内のみ。NodePort / LoadBalancer / HTTPRoute は追加しない |

PGO と PostgresCluster CR を GitOps 管理する。生成される StatefulSet / Service / PVC を別の manifest で二重管理しない。
PostgreSQL は単一 instance から開始し、pgBackRest バックアップと WAL 保管を初期導入に含める。
PGO の固定バージョンは PostgreSQL 18・稼働 Kubernetes・対応イメージの互換表で選定する。
Operator の監視対象は必要な Namespace に限定し、CRD・RBAC・Operator 自体の更新も検証する。
単一 DB の停止・更新は全利用アプリに影響する。NFS 共有も単一障害点であり、この計画は可用性向上を保証しない。
PGO、PostgreSQL とバックアップ Job のイメージは Harbor が停止していても取得できる公開レジストリから取得する。
PGDATA・volume mount・UID/GID は採用する Crunchy イメージと PGO の設定に合わせて検証し、Harbor イメージのパスを転用しない。

### ストレージとデータ保持

- NFS クライアントの実マウントが `hard` であること、サーバーの export が永続化を保証する設定であることを確認する。
  PostgreSQL 公式は `hard` を要求し、Linux NFS サーバーの `sync` export を強く推奨する。
  クライアントの `sync` mount とは別の設定である。[公式資料](https://www.postgresql.org/docs/17/creating-cluster.html)
- root squash、所有権、fsync、再起動後の読み書きを検証する。NFS 障害時の I/O 待ちも監視対象にする。
- 10Gi は PVC の要求量。共有 NFS 上で容量の予約・上限が保証されるとは扱わない。
- 新規・旧 DB とも PVC 保持、PV reclaim policy、ArgoCD prune の挙動を明示的に確認する。
  新規 DB PV は `Retain` とする運用を用意し、既存共有 StorageClass の設定を一括変更しない。
- `resourcePolicy: keep` だけで ArgoCD の削除保護を保証しない。PostgresCluster / Application / CRD の削除から PGO 生成 PVC への連鎖を検証し、削除確認ポリシーを設計する。
- 同じ PGDATA を複数 Pod で同時利用しない。ノード障害時の強制削除・再配置は旧プロセス停止を確認して行う。

### 共用ユーザーと接続契約

- アプリ共用のログインロール `app` を使う。DB / schema はアプリの要件に合わせ、
  共用ロールに DDL / migration に必要な所有権を与える。
  アプリに SUPERUSER / CREATEDB / CREATEROLE / REPLICATION を与えない。
- `PUBLIC` の DB CONNECT / TEMP、schema CREATE を整理し、共用ロールに必要な権限を付与する。
  管理ロールを別にする。アプリ間でのデータ参照は許容する。
- DB / ロールは `PostgresCluster.spec.users` に宣言し、作成とパスワード反映を PGO に委ねる。
  PUBLIC 権限の制限・所有権など追加 SQL が必要な部分だけ、再実行可能な管理 Job で補う。
  補助 SQL Job は PGO 管理ロールの属性・パスワードを直接 ALTER しない。DB / ロールを Git から消すだけで DROP しない。
- DB パスワードの正本は **Pulumi ESC** とする。ESO が `database` の入力専用 Secret と
  各利用 Namespace の接続 Secret に同じ ESC 値を配布する。Harbor 用は `harbor/harbor-database-secret`（キー `password`）。
  ユーザー名・DB 名・host は Git の非機密設定とする。管理資格情報をアプリ Namespace に配布しない。
- ESO の入力 Secret と PGO の `shared-postgresql-pguser-<user>` Secret を分ける。
  PGO Secret は PGO が管理し、ESO は直接所有・定期上書きしない。
  限定 RBAC の資格情報反映 Job が ESC 由来パスワードを PGO の custom password 手順で反映する。
  パスワード変更時だけ `password` を更新して古い `verifier` を消去し、PGO に SCRAM verifier 生成と DB 反映を任せる。
  同一値の再実行では verifier を消さず、PGO が付ける接続情報・metadata は保持する。
  初回 Secret の事前投入または PGO 生成後の更新順序は固定版で検証し、認証付き SQL 成功まで準備完了にしない。
- 反映 Job は Secret の変更を契機に再実行できる仕組みを用意する。ESO の同期は ArgoCD の再同期を自動発火しないため、
  PostSync Job のみで継続的なローテーションが実現できるとは扱わない。
  ローテーション手順はアプリを停止 / 排出 → ESC 更新 → ESO 同期 → Job → PGO の DB 反映確認 → アプリ再接続とする。
  同一ロールで新旧パスワードが同時に有効とは仮定しない。Job に秘密値をログ出力させない。
- 再構築では ESC から資格情報を再供給し、復元された DB に PGO 経由で反映して SQL 接続を確認後にアプリを解放する。
  pgBackRest のバックアップに Kubernetes Secret が含まれるとは扱わない。
  ESC 自体の復旧・bootstrap 認証・必要な暗号化鍵の保管も独立した復旧手順に含める。
- NetworkPolicy は namespaceSelector と podSelector の AND で Harbor、登録アプリ、管理・バックアップ Job を許可する。
  既存ポリシーとの合算、DNS と監視通信、許可・拒否の実通信を確認する。DB 認証は常に必須。
- PostgreSQL TLS と SCRAM 認証を用意し、Harbor は `sslmode: verify-full` を目標にする。
  Service DNS の SAN・CA 配布・chart の CA mount 方法を検証し、検証無効化を既定にしない。
  Certificate は既存規約に従い `infrastructure/security/cert-manager/` に集約する。
- Harbor のプール初期案は `maxOpenConns: 10` / `maxIdleConns: 3`。
  core / jobservice と、追加する場合の exporter の Pod 数と rolling update の一時増加分、他アプリ、管理接続を合計して 100 以下に収める。
  ロール接続上限も設定し、追加アプリは接続予算を申告する。負荷試験で確定する。

### Secret 数の予算（25 個枠）

2026-10-18 の実クラスタでは ExternalSecret 17 件、重複を除く ESC remoteRef.key は 20 種類。
Grafana は ESO Password generator を使い、ESC を参照しない。
ただし、これは ESC の課金・利用枠の消費数ではない。ESC は最新 environment revision の
`fn::secret` / `fn::open::*` 定義（pulumi-stacks を除く）を数えるため、同一値の複数 Namespace への配布数や
参照キー数と一致するとは限らない。[Pulumi 公式 FAQ](https://www.pulumi.com/docs/support/faq/secrets-config/)

- 実装前に ESC 側の実消費数を確認し、未参照の secret や他 environment も含めて 25 個枠を評価する。
- DB 管理用 `postgresql.admin_password` とアプリ共用 `postgresql.password` の各1個を ESC に保存する。
  他アプリは同じ値を参照し、パスワードを追加しない。
  同じ値を database とアプリ Namespace に配布しても、ESC に二重登録しない。
- 実消費が20個の場合、初期追加後22個で残り3個。バックアップ保存先資格情報・暗号化鍵などは別途計上する。
  ユーザー名・DB 名・host は非機密設定、SCRAM verifier は PGO が生成するため ESC に別保存しない。
- cert-manager / PGO が生成する内部 Secret は ESC に保存しなければその枠を消費しない。
  枠節約のためにアプリ間でパスワードを共有しない。

## 予定するファイル変更

| パス | 変更内容 |
|---|---|
| `manifests/platform/pgo/`（新規） | バージョン固定した Operator / CRD / RBAC の repo-local wrapper |
| `manifests/platform/shared-postgresql/`（新規） | PostgresCluster、pgBackRest 設定、補助 Job、NetworkPolicy、Kustomization |
| `manifests/bootstrap/applications/platform/pgo.yaml`（新規） | Operator の独立 Application |
| `manifests/bootstrap/applications/platform/shared-postgresql.yaml`（新規） | HEAD を参照する Application |
| `manifests/bootstrap/applications/platform/kustomization.yaml` | Application 登録 |
| `manifests/core/namespaces.yaml` | `database` の存在・ラベル確認、必要な差分のみ追加 |
| `manifests/platform/secrets/external-secrets/` | config-secrets 配下の新規 `postgresql/` に ESC 入力・アプリ用 ExternalSecret を追加、親 Kustomization 登録 |
| `manifests/platform/argocd-config/` | Operator Namespace の AppProject 許可、PostgresCluster health と依存順序 |
| `manifests/infrastructure/security/cert-manager/` | DB TLS 証明書と登録 |
| `manifests/platform/harbor/values.yaml` | external 接続、Secret、CA、接続数設定 |
| `manifests/platform/observability/` | DB・容量・バックアップ監視 |
| `docs/diagrams/app-of-apps-sync-wave.md` | 新 owner と依存関係 |
| `docs/manifests.md`, `docs/secrets.md`, `docs/operations.md` | 実装後の利用・保守手順 |

sync wave 案は pgo 8 / config-secrets 9 → shared-postgresql 10 → Harbor 11。
実装時に他の wave 8〜11 アプリと依存関係を確認する。CRD Established / Operator Ready、ESC 由来 Secret Ready、
DB 接続、ロール作成・パスワード反映完了を個別に待つ。
Secret の配布は ESC だけを参照し、PGO 生成 Secret を前段の config-secrets から参照しないため循環しない。
資格情報反映 Job と DB 検証 Job は database 内の入力 Secret を使用する。
App-of-Apps の番号だけでは child Application の内部準備完了を保証しない。
再構築を手動の段階同期に依存させず、以下の起動待機と復旧ゲートを実装する。

## クラスタ再構築時の起動順と待機条件

必要な順序は **NFS / DNS / ESO / 証明書・PGO / CRD → PostgreSQL → DB・ロール準備 / ESC 資格情報反映 / 復元完了 → Harbor → 利用アプリ**。
Pod が Running になっただけでは次に進めない。Harbor 自身の schema migration はこの待機後に実行する。

### 自動待機の実装方針

1. **ArgoCD の順序制御**: PGO / CRD、wave 9 の ESC 資格情報配布、wave 10 の共通 DB、wave 11 の Harbor の順に作成する。
   PostgresCluster の status を固定版仕様に基づき評価し、CR 作成だけを Healthy としない。
   現行 `manifests/platform/argocd-config/argocd-config.yaml` には Application 用 custom health がない。
   Application の health 評価を追加する場合は、status 未取得を Progressing とし、対象 revision の同期と
   子の準備完了を評価する。bootstrap が root Application を適用する前に設定が有効になる経路を確認する。
   既存の前段 Application が後段のリソースを待つ循環も検査し、全体を止める設定を無条件に追加しない。
   Application health は標準で提供されないため wave 単独では待機を保証できない。
   [ArgoCD 公式資料](https://argo-cd.readthedocs.io/en/stable/operator-manual/health/)
2. **DB 側の準備**: PVC Bound、TLS / ESC 入力 Secret Ready、PGO のユーザー Secret 作成を確認し、
   資格情報反映 Job → PGO による DB 反映 → ESC 資格情報での SQL 接続確認 → 補助 SQL Job の順に進める。
   PGO が作成した DB・ロールを確認し、補助 Job は追加権限設定と、選択された復旧方式の完了を確認する。
   初回に DB 自体がまだない PreSync で待つ構成は避け、DB リソースの後続 Sync wave に置く。
3. **利用側の起動待機**: Harbor core の `core.initContainers` に、実際の接続先・アプリ資格情報・TLS で
   `SELECT 1` と準備完了を確認する待機処理を追加する。DB を直接利用する他コンポーネントにも必要に応じて付ける。
   TCP 接続や `pg_isready` だけで成功にしない。初回作成前の Harbor テーブルは要求しない。
   復旧世代に対応した準備完了マーカーを管理 Job が記録し、復元中に SQL が通るだけでは起動させない。
   待機用イメージも Harbor に依存させない。Secret 未作成、DB 遅延、認証失敗時は本体を起動せず、
   再試行・待機理由のログ・長時間待機のアラートを設ける。

initContainer は ArgoCD を経由しない Pod 再作成・ノード再起動にも適用される。
起動後の DB 障害は initContainer では扱えないため、アプリの再接続と readiness も検証する。
他アプリを共通 DB に追加するときも同じ起動待機を利用条件にする。

### データの状態に応じた再構築

| 状態 | 起動を許可する条件 |
|---|---|
| 完全な新規環境 | 明示的な新規作成モードで DB・ロールを作成し、空 DB であることを確認して準備完了を記録 |
| NFS 上にデータが残る | 保存した PV / NFS パス・DB 識別情報に基づいて既存データを再接続し、整合性と資格情報を確認 |
| バックアップから復旧 | アプリ停止状態で restore・所有権・件数・sequence 等を検証し、その復旧世代の完了を記録してから解放 |

既存環境の再構築では既定を復旧待機にする。DB や PVC が見つからないことを、新規作成の許可と見なさない。
NFS subdir provisioner が新しい PVC UID に対して空ディレクトリを作るケースを考慮し、
以前の PVC 名を作り直すだけで既存データが戻るとは扱わない。再バインド用の PV 情報をバックアップする。
旧バックアップ内の完了マーカーを信用せず、今回の復旧世代を照合する。
復旧モード・期待する世代は DB に依存しない Git 管理設定として bootstrap 前に指定し、手順書に組み込む。
Harbor の DB と Registry データ・Secret の復旧点が対応することも起動解放の条件とする。

実装では `automation/scripts/run.sh` → `automation/platform/platform-deploy.sh` の既存 bootstrap 経路を確認し、
復旧モード指定・待機・失敗の報告を統合する。恒常リソースは引き続き ArgoCD 管理とする。

### 再構築の受け入れ試験

- [ ] 空の検証クラスタで、NFS・ESO・DB の起動を意図的に遅延させても Harbor 本体は待機する。
- [ ] DB / ロール未作成、認証・TLS 失敗、復旧未完了の各ケースで起動ゲートが閉じる。
- [ ] DB 準備完了後に手動の Pod 再起動なしで Harbor が起動し、migration と push / pull が成功する。
- [ ] NFS データ保持の再構築で既存データを再利用し、新しい空 DB に接続しない。
- [ ] バックアップ復旧中に Harbor が空 schema を作らず、今回の復旧完了後にだけ起動する。
- [ ] 全ノード再起動、および起動済み Harbor に対する DB 再起動後も復帰する。
- [ ] PostgreSQL とその準備・待機・復旧 Job は、Harbor が停止し image cache がない状態でも起動できる。

監査スクリプトの名前・パス依存、GitOps チェック、ExternalSecret domain の検査も併せて更新する。

## 実装・移行の順序

### 1. 事前確認と基盤追加（Harbor の接続はまだ変更しない）

- [ ] PostgreSQL / Harbor の実稼働バージョン、DB 一覧・owner・拡張・encoding・locale・照合順序を再取得。
- [ ] PGO / Crunchy PostgreSQL / pgBackRest の対応版・取得条件・patch / digest を確認。同一メジャーでも locale provider 差を検証する。
- [ ] NFS の保存先・マウント条件・空き容量・削除保護、クラスタ余剰 CPU / メモリを確認。
- [ ] PGO / CRD、Secret、TLS、PostgresCluster、ESO 配布、補助 Job、バックアップ、監視を追加して同期。
- [ ] DB `registry` とロール `harbor` を作成。再実行・資格情報更新・別アプリ用 DB 作成を試験。
- [ ] 別アプリ用の検証 DB で接続成功・アプリ間接続拒否を確認。

### 2. 移行リハーサル

- [ ] 現行 DB の `pg_dump -Fc` を取得し、隔離された検証 DB へ復元。
  クライアントはサーバーと同じメジャー 18 を使う。ダンプは機密データとして扱い、Git / CI artifact / ログへ出さない。
- [ ] 移行先 DB は元と互換な encoding / locale で空の状態から作成する。
  `pg_restore --no-owner --no-acl --exit-on-error` と対象ロールへの所有権付与を組み合わせて検証する。
  元の superuser / 全ロールを共通 DB に一括復元しない。
- [ ] テーブル件数、sequence、schema migration version、権限、Harbor 起動を検証する。
  検証 Harbor は本番の Registry / Redis / webhook / ジョブ実行先から隔離する。
- [ ] バックアップ・復元・検証の所要時間を測り、停止枠と中止判断時刻を決める。
  DB が小さくても所要時間を推定だけで約束しない。

### 3. 本番切り替え（メンテナンス時間内）

1. 対象 Harbor のバージョンを固定し、自動更新が重ならないようにする。
   Root 側の定義で自動同期設定が戻される経路も含め、Harbor の自動同期・selfHeal を管理する。
   停止状態と復旧状態を GitOps で再現できる変更を用意し、DB 設定だけ先に自動反映させない。
2. CI push、ユーザー操作、cleanup CronJob、GC / scan / replication などのバックグラウンド更新を止め、実行中処理を排出する。
   外部入口をメンテナンス状態にし、core / jobservice 等の書き込み元を停止。DB 接続・進行中トランザクションを確認する。
   Harbor の read-only 設定だけで完全な書き込み停止と見なさない。
3. 最終ダンプを採取し、checksum と保管先を記録する。
   Registry データ・必要な Redis 状態・Harbor Secret も復旧できる保全点を確保し、DB と画像の整合性を保つ。
4. 新 DB `registry` へ最終ダンプを復元し、件数・所有権・sequence・接続権限を検証。
5. `database.type: external`、接続先・共用ロール・Secret・TLS・プール設定を同期。
   内蔵 StatefulSet が削除される差分と旧 PVC が残ることを確認してから適用する。
6. 外部書き込みを閉じたまま Harbor を起動し、DB migration、ログイン、プロジェクト・artifact 一覧、既存 image pull を確認。
7. 確認後に入口とジョブを再開し、専用テスト project で push / pull / scan を実施する。
   ここからは新 DB が正本となる。ArgoCD の自動同期を通常状態へ戻す。

### 4. 安定化と旧 DB 廃止

- [ ] 7 日間を初期観察期間とし、接続数・エラー・遅延・空き容量・バックアップ成功を確認。
- [ ] 新 DB のバックアップから別 DB への復元成功を確認してから旧 DB の廃止を判断。
- [ ] 旧 PVC は切り戻し用に保持し、観察期間終了だけで自動削除しない。
  保持期限・最終バックアップ・対象 PV / NFS パスを確認して別作業として削除する。
- [ ] 成果を運用 docs に反映し、他アプリの追加手順を確定する。

## 切り戻し

- **新 DB への切り替え前**: 旧 DB を正本として Harbor の停止設定を戻し再開する。
- **切り替え後、業務書き込み再開前**: 新側を停止し、旧 PVC を再利用する内蔵 DB と固定した旧 Harbor 構成を復元する。
  接続検証時の migration 等の変更は新 DB 側に限定されることを確認する。
- **書き込み再開後**: 単なる `database.type: internal` への差し戻しは禁止。
  再停止し、新 DB をバックアップして旧環境へ戻すリハーサル済み手順、または新 DB を前進修復する。
  Registry と DB の整合性も確認し、旧保全点へ戻す場合のデータ損失は明示して判断する。
- 全ケースで同時書き込みを防止し、ArgoCD が切り戻しを打ち消さないことと、最後に Git の正本へ戻ることを確認する。

## バックアップ・監視・他アプリ追加

- PGO 統合 pgBackRest で、週次 full・日次 differential・継続 WAL アーカイブを初期案とする。
  14日分以上の復旧範囲を確保できる full 世代数と依存バックアップ / WAL の保持を設定し、実際の復旧可能期間を検証する。
  月1回、隔離した PostgresCluster への復元と PITR を試験する。暫定目標は RPO 24時間 / RTO 2時間。
  WAL 保管があるだけで短い RPO を保証せず、最終 archive 時刻と復元実測で判定する。
- 初回の Harbor 移行は引き続き `pg_dump` / `pg_restore`。移行完了後に pgBackRest 初回 full を取得する。
  pgBackRest の復旧単位は共通 PostgreSQL 全体なので、単一アプリだけ戻す場合は隔離クラスタに復元してから
  対象 DB を論理 export / import する。他アプリを巻き戻さない。
- 2026-10-19 のユーザー指定により、外付け SSD 上の NFS に専用 pgBackRest PVC を設ける。
  DB とバックアップはディレクトリを分離する。同一 SSD / NFS サーバーの障害では両方が失われる制約を記録する。
- ロール・権限の宣言、ESC の復旧手順、TLS、PostgreSQL 設定も復旧対象。`pg_dump` だけで全体復旧できるとは扱わない。
- 監視は DB 稼働、接続枯渇、長時間 query / lock、NFS 空き容量・I/O、バックアップ失敗・最終成功時刻を含める。
- アプリ追加は DB 名・ロール・必要拡張・接続予算・RPO を登録 → Secret / 権限作成 → 通信許可 → 接続・隔離試験 → workload 接続設定の順。
  バックアップ対象への追加を同時に行う。独自メジャーや特権拡張が必要なアプリは共用対象にしない。

## 完了条件と検証

- [x] `automation/scripts/ci/validate.sh` が成功し、GitOps 参照・policy・Kustomize / kubeconform が通る。
- [x] Harbor の内部 PostgreSQL Pod はなく、外部 DB 接続と既存 artifact の利用が成功する。
- [x] Redis と既存ストレージの意図しない変更がない。
- [x] Harbor ロールの別 DB 接続拒否と、未許可 Pod からの通信拒否を確認する。
- [ ] 他アプリ追加時に共用 app ロールでの接続・DB / schema 権限・接続予算を確認する。
- [ ] DB Pod 再起動後もデータ保持・再接続が成功し、起動が Harbor に依存しない。
- [x] pgBackRest から隔離 PostgresCluster への復元とデータ一致を確認する。
- [ ] 時刻指定 PITR と単一アプリ DB の取り出しの演習。
- [x] ESC 入力 Secret / PGO 管理 Secret / アプリ Secret を分離し、PGO への反映とアプリ認証が成功する。
- [ ] 運用中のパスワードローテーションと全クラスタ再構築の演習。
- [ ] PGO / CRD の再構築・更新、PostgresCluster / PVC の削除保護、切り戻しリハーサルが成功する。
- [x] CI に固定版 PostgresCluster の schema 検証を追加し、未知 CRD として無条件スキップしない。
- [x] 自動同期・定期バックアップが有効になり、移行用の停止設定を解除する。
- [ ] 専用 DB / バックアップ監視の拡充。

## 実装開始時に確定する項目

PGO の固定版・CRD schema・互換イメージ、NFS の実体と安全な mount / export、指定 NFS バックアップ先、TLS の CA 配布、
実測した接続・メモリ予算、移行停止枠を確定する。いずれも未確認のまま本番切り替えへ進めない。

## 参考

- [Harbor Helm 外部 DB 設定](https://github.com/goharbor/harbor-helm)（実装時は repo 内 chart 1.19.4 のテンプレートを優先）
- [Harbor 外部 DB の利用](https://goharbor.io/docs/main/install-config/harbor-ha-helm/)
- [PostgreSQL pg_dump](https://www.postgresql.org/docs/current/app-pgdump.html)
- [PostgreSQL NFS 要件](https://www.postgresql.org/docs/17/creating-cluster.html)

- [PGO ユーザー・資格情報管理](https://access.crunchydata.com/documentation/postgres-operator/latest/architecture/user-management)
- [PGO バックアップ](https://access.crunchydata.com/documentation/postgres-operator/latest/architecture/backups)
- [PGO 復旧](https://access.crunchydata.com/documentation/postgres-operator/latest/tutorials/backups-disaster-recovery/disaster-recovery)
- [PGO 互換表](https://access.crunchydata.com/documentation/postgres-operator/latest/references/components)

## 移行実施記録

- Operator は PGO 6.0.3 を固定。同梱 chart の PostgreSQL 18.6 / pgBackRest 2.59.0 に合わせる。
- ESC に管理用・Harbor 用パスワードを追加済み。秘密値は Git に保存しない。
- 稼働中 registry DB の事前ダンプを操作端末の権限 0600 のファイルに保存。最終切り替え用ではない。
- バックアップ先は 2026-10-19 にユーザーが既存 NFS を指定。復元検証完了後に切り替える。
- `f762cee` で PGO / CRD / ESO 定義を GitOps 反映。CI 相当の全検証は成功。
- PGO イメージ取得は成功したが worker2 で `Fatal glibc error: CPU does not support x86-64-v2`。
  worker1 も `QEMU Virtual CPU version 2.5+` で必要な命令が不足している。
  Operator は replicas 0 にして再起動ループを停止し、VM CPU 設定の修正待ちとする。
  PostgresCluster は未作成、Harbor は内部 DB のまま正常稼働。
- 再開条件: KVM ホスト CPU 対応確認 → VM CPU 設定と安全な順次再起動 → PGO 起動確認、
  およびユーザー指定 NFS でのバックアップ・復元検証。ノード再起動には既存 workload の退避・復帰確認も含める。

### 2026-10-19 本番切り替え

- 両ワーカーを host-model でコールド起動。x86-64-v2 を満たし、PGO / PostgreSQL は正常起動。
  当初の host-passthrough で worker1 に libc segfault / 停止を観測したため変更した。
- NFS は hard / NFSv4.2、サーバー export は sync。新しい StorageClass は nfs-postgresql / Retain。
- PGO 6.0.3、PostgreSQL 18.6、pgBackRest 2.59.0。新規データ PVC と repo を作成。
- 管理用・Harbor 用パスワードは ESC が正本。資格情報 Job の TLS / SQL 確認は成功。
  PGO 証明書の SAN に合わせて接続名を `shared-postgresql-primary.database.svc` とした。
- 事前 dump の復元後、pgBackRest full backup から独立クローンを作成。
  全 49 テーブルの内容ハッシュ・件数と 47 シーケンスが一致。検証用クローンは GitOps から削除済み。
- `b5fa78f` で入口・core・jobservice・registry・trivy・cleanup を停止し、旧 registry 接続数 0 を確認。
- 最終 dump と globals、比較結果、PV inventory をローカル権限 0600 と NFS に保管。
  NFS: `/mnt/k8s-storage/nfs-share/harbor-pgo-migration-20261019/`。
  最終 dump SHA256: `6143994d840d04d9a622cae16426a658a8dddfc09f3b5c87094d4404e0fc5d74`。
- 最終復元の全テーブル・シーケンス比較が一致した後、管理者所有の復元マーカーを記録。
  `final-migration-20261019` full backup は 2026-10-19 07:21:41 UTC に成功。
- `0533ee8` で外部 DB へ切り替え。jobservice も DB を使用するため `3c35222` で CA / 起動ゲートを追加。
  core と jobservice の両方で起動ゲート通過を確認し、API health は全コンポーネント healthy。
- 旧内蔵 DB Pod は削除済み。旧 PVC は保持し PV は Retain。Redis と既存データ PVC は継続使用。
- 再構築時の空 DB による初期化を起動ゲートで防ぐ。全クラスタ破棄を伴う復旧演習、PITR、
  ローテーション演習、専用 DB 監視の拡充は別途残る。未実施の演習を完了扱いにはしない。

- 最終機能試験: Pulumi 管理の管理者資格情報で API 認証、既存 hitomi-upload-viewer イメージの pull、
  一時リポジトリへの push、Trivy scan Success、検証用リポジトリ削除がすべて成功。
- 許可外ラベルの Harbor Pod から PostgreSQL への TCP 接続拒否を実測。
- 修正後の CI 相当の全検証が成功。CA 配布漏れ・外部 DB 化・既存 Redis / Trivy ストレージを
  Helm 展開結果で検査する回帰テストを追加し、資格情報テストと合わせて 4 件成功。
- 起動準備中の失敗 Job は削除し、定期資格情報 Job は成功を継続。Harbor / PGO / 共通 DB は Synced / Healthy。


### 2026-10-19 共用ユーザーへの変更

- 個人クラスタの運用方針として、Harbor と他アプリのログインユーザーを `app` に統一した。
  管理用 `postgres` は別に保持し、アプリ間のロール分離・個別パスワードは採用しない。
- ESC を `postgresql.password` に統一し、旧 `postgresql.harbor_password` を削除した。
  暗号化した既存値を引き継ぎ、ESO → PGO / Harbor の同期と TLS 接続を確認した。
- `registry` と既存オブジェクトの所有権を `app` に移管し、復元マーカーの参照権限を付与した。
  core / jobservice が `app` 接続へ移行した後、旧 `harbor` ロールを削除した。
- `app` でテーブル作成・書き込みをトランザクション内で検証し、ROLLBACK した。
  既存 artifact 15 件、復元マーカー、Harbor 全コンポーネントの healthy を確認した。
- 他アプリ追加時も `postgresql.password` を配布する。DB / schema、CA 配布、NetworkPolicy と
  全アプリ合計の接続予算を設定する。ESC パスワードとログインロールは追加しない。
- 変更後の NFS full backup `20261019-123334F` が 12:34:04 UTC に完了した。
  CI 相当検証と PostgreSQL 回帰テスト 4 件が成功し、ArgoCD の 3 Application は Synced / Healthy。
  ESC の `fn::secret` は 22 個のまま。
