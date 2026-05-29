# 構造改革ステータス

最終更新日: 2026-05-29

## Current Phase

- PH0: Target Operating Model（完了見込み）

## This Week

- [x] `tasks/` 管理基盤の初期作成
- [x] PH0 方針の確定（旧仕様完全削除 / main 併存なし）
- [x] 主要リスクの初期登録
- [ ] PH1 実装計画の具体化（bootstrap 責務の切り出し）

## In Progress

- PH1 準備: bootstrap 入口最小化の実装計画レビュー

## Blocked

- なし

## Completed This Week

- `tasks/` ディレクトリと PH ドキュメントを作成
- PH2/PH3/PH4/PH5/PH6 の方針を「旧仕様完全削除」前提へ更新
- リスク台帳に owner/期限管理を導入

## Next Gate

- Gate B: PH1 完了条件の達成

## Decision Needed

- なし（PH0 主要判断は確定）

## Notes

- main ブランチに旧新併存を残さない
- cutover 時の停止時間は許容（snapshot/rollback 前提）
