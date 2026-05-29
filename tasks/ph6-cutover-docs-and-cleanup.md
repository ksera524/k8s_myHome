# PH6: Cutover, Docs, and Cleanup

## 目的

- 新構造へ切替を完了し、ドキュメントと実装の不一致を解消する
- 旧仕様を main から完全削除し、運用窓口を新構造へ一本化する

## 背景

- 改革途中は旧新フローが併存し、運用混乱を招きやすい

## スコープ

- cutover チェック
- ドキュメント更新
- 旧資産の即時削除

## 非ゴール

- 追加の大規模機能導入

## 具体タスク

1. cutover チェックリストを作成し運用実施
2. `README.md` と `docs/README.md` を新責務に合わせ更新
3. `docs/setup-guide.md` と `docs/applications.md` を新フローへ更新
4. `docs/gitops-design.md` / `docs/operations-guide.md` / `docs/troubleshooting.md` を最終整合
5. `docs/manifest-layout.md` / `docs/kubernetes-architecture.md` / `manifests/README.md` を最終整合
6. 旧 workflow/script/manifest の削除一覧を作成
7. cutover 時点で旧資産を削除し、deprecate 期間を置かない
8. 残課題を backlog 化し、改革完了を宣言
9. grep ベースで旧記述が repo に残っていないことを確認

## 変更対象

- `README.md`
- `docs/README.md`
- `docs/setup-guide.md`
- `docs/applications.md`
- `docs/gitops-design.md`
- `docs/operations-guide.md`
- `docs/troubleshooting.md`
- `docs/manifest-layout.md`
- `docs/kubernetes-architecture.md`
- `manifests/README.md`
- `tasks/cutover-checklist.md`
- `tasks/backlog.md`
- 旧 workflow/script/manifest

## 検証

1. `tasks/cutover-checklist.md` の必須項目が 100% 完了していること
2. 旧手順への依存が残っていないこと
3. 以下が grep 0 件であること（対象: `manifests/`, `automation/`, `docs/`, `.github/`, `Makefile`）
   - `user-applications|user-application-definitions`
   - `add-runner\.sh|add-runners-bulk\.sh|add-runners-all|arc_repositories`
   - `kubectl apply -f manifests/bootstrap/app-of-apps.yaml`（旧手順の場合）

## 完了条件

1. docs と実装が一致している
2. 旧フローが削除済み
3. cutover チェック項目が全件完了
4. 残課題が `backlog` として明確化されている
5. main ブランチに旧仕様が残っていない
6. `legacy-removal-inventory.md` に紐づく legacy 関連例外が Open 0 件
