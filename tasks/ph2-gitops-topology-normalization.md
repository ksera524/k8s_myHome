# PH2: GitOps Topology Normalization

## 目的

- App-of-Apps 配下の所有関係を正規化し、重複管理と誤解をなくす
- owner を一意化し、差分レビュー可能な粒度へ再構成する

## 背景

- 単一巨大ファイルと二重経路により、どの Application が owner か追いにくい

## スコープ

- Application 定義の分割
- owner 一意化
- `user-applications` / `user-application-definitions` の完全廃止
- 図と実装の一致

## 非ゴール

- app repo の CI 方式変更

## 具体タスク

1. `manifests/bootstrap/app-of-apps.yaml` を root Application 1件へ再定義
2. child Application を `manifests/bootstrap/applications/` に 1 Application 1 file で分割
3. `user-applications` / `user-application-definitions` を完全削除
4. `manifests/bootstrap/applications/user-apps/` を apps owner の正本として整理
5. AppProject と destination 制約を見直し、owner 一意性を担保
6. `automation/platform/platform-deploy.sh` と `automation/scripts/verify.sh` の旧 owner 参照を更新
7. `.github/workflows/weekly-version-audit.yml` の `app-of-apps.yaml` 依存を更新
8. `docs/diagrams/app-of-apps-sync-wave.md` を実装と同期
9. PH2 判定用の暫定 owner 重複チェック手順を定義し実行
10. 所有重複検出チェックの恒久実装を PH5 へ引き継ぎ

## 変更対象

- `manifests/bootstrap/`
- `manifests/bootstrap/applications/`
- `manifests/bootstrap/applications/user-apps/`
- `manifests/platform/argocd-config/`
- `automation/platform/platform-deploy.sh`
- `automation/scripts/verify.sh`
- `automation/scripts/ci/`
- `.github/workflows/weekly-version-audit.yml`
- `docs/diagrams/app-of-apps-sync-wave.md`
- `docs/setup-guide.md`
- `docs/gitops-design.md`
- `docs/external-access-guide.md`

## 検証

1. 全 child app の owner が一意であること
2. 図と manifest の依存順が一致していること
3. `user-applications` / `user-application-definitions` 参照が repo から消えていること
4. child Application 追加/変更が「1ファイル差分」でレビュー可能であること

## 完了条件

1. Application 所有重複がない
2. `user-applications` / `user-application-definitions` が削除済み
3. App-of-Apps 構成が差分レビュー可能な粒度になっている
4. 依存順を docs で再現できる
5. bootstrap/verify/audit/docs の参照先が新トポロジへ切り替わっている
6. owner 重複チェック手順（PH5 実装前の暫定チェック）が定義・実行済み
