# PostgreSQL の更新と CI

共通 PostgreSQL 基盤は、Renovate が PGO chart の更新を検出して一括 PR を作成する。
個別イメージの最新タグを独立に追わず、更新先 chart に同梱された推奨構成を採用する。
PostgreSQL のメジャーは現在の `spec.postgresVersion` を維持する。

## 更新の流れ

1. 毎日の Renovate が OCI の PGO chart を検出する。
2. 同一リポジトリの `github-actions[bot]` が作った `renovate/` PR に対して、
   main の信頼済みスクリプトが chart を取得・同梱し、次のイメージを同期する。
   - PostgreSQL 本体と pgBackRest
   - 資格情報 Job と Harbor core / jobservice の起動待機コンテナ
   - 手動復元用のサンプル定義
3. 同期コミット後の HEAD に既存の検証 workflow を dispatch する。
4. 整合性・マニフェスト検証と、一時 kind クラスタでの実行テストを通してから手動マージする。

OCI の Docker datasource では公開日時が取得できないことがあるため、PGO chart に限り
`minimumReleaseAgeBehaviour: timestamp-optional` を設定する。日時を取得できない場合は
3 日経過を保証せず PR を作成し、マージ判断は人が行う。他の依存の設定は変更しない。
PGO major 更新は Dependency Dashboard の承認対象となる。

同期処理は PR 側のスクリプトや Git hooks を実行しない。取得元を Crunchy の公式 OCI に限定し、
archive のパス・ファイル種別・chart metadata を確認する。同時更新された PR は通常の push で上書きを拒否する。
更新先が現在の PostgreSQL major を提供しない場合は失敗し、自動的に別 major へ切り替えない。

## 整合性チェック

```sh
nix develop --command python3 automation/scripts/ci/postgresql-versions.py
```

chart version、同梱 chart metadata、Operator の版、PostgreSQL major、
PostgreSQL / pgBackRest と補助コンテナのイメージを照合する。
公式 chart のデフォルトと厳密に一致させるため、独立した最新 minor / build は採用しない。
イメージの取得可否・実行アーキテクチャへの対応は後述の実行テストで確認する。
CRD の schema は指定した chart から取得し、kubeconform でも検証する。

手動で PGO の version を変更した場合は、次で関連ファイルを揃える。

```sh
nix develop --command python3 automation/scripts/ci/postgresql-versions.py --sync
```

## 実行テスト

`ci-deploy-validate.yml` の `postgresql-runtime` job が対象ファイルの変更時に起動する。
GitHub Actions の一時 kind クラスタを使い、本番 kubeconfig・NFS・ESC のトークンを必要としない。
検証用 `app` パスワードは PGO が生成し、SQL 接続時の標準入力で渡す。

1. PR の base commit の PGO / DB / pgBackRest を起動する。
2. 本番と同じ `bootstrap.sql` で所有権を設定し、検証データを作成する。
3. PR の PGO / DB / pgBackRest を適用し、DB Pod を再起動する。
4. TLS verify-full / app 認証、DB major、データ内容、読み書きを確認する。
5. 更新後の手動 full backup の ID と成功を確認する。
6. 別の PostgresCluster へ復元し、検証データの件数・内容と読み書きを確認する。
7. 成否にかかわらず診断ログを保存し、一時クラスタを削除する。

比較する版が同じ場合も、再起動・バックアップ・復元のテストを実施する。
DB major が異なる場合は失敗させる。メジャー移行、PITR、更新前バックアップの更新後環境での復元、
本番 NFS、ESC / ESO、Harbor 全体の機能試験はこのテストの検証範囲に含まない。
本番の復旧演習を代替したという扱いにはしない。

ローカルで実行するには Docker を起動して次を実行する。

```sh
nix develop --command python3 automation/scripts/ci/postgresql-runtime.py \
  --base-ref origin/main --logs /tmp/postgresql-runtime-logs
```

kind は flake.lock の Nix パッケージに固定し、その版が既定とする node image を使う。
テスト専用 kubeconfig を明示し、利用者の既存 context を参照・更新しない。
実行時間の目標は 10〜20 分、CI 全体の上限は 30 分。ダウンロード速度により変わる。
Actions の手動実行で `postgresql_runtime=true` を指定すると、変更がなくても実行する。
通常の Renovate dispatch は PostgreSQL 関連に変更がある場合だけ実行する。
診断ログは Actions artifact `postgresql-runtime-logs` に 7 日間保存する。

## 参照

- [PGO のコンポーネント対応表](https://access.crunchydata.com/documentation/postgres-operator/latest/references/components)
- [PGO のバックアップとクローン](https://access.crunchydata.com/documentation/postgres-operator/latest/tutorials/backups-disaster-recovery/disaster-recovery)
- [Renovate の custom manager](https://docs.renovatebot.com/modules/manager/regex/)
