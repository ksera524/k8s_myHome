# PH0: Target Operating Model

## 目的

- 構造改革の最終形と責務境界を合意し、以降の実装判断をブレさせない
- main に旧新併存を残さず、旧仕様を最終的に完全削除する方針を固定する

## 背景

- `automation/`, `manifests/`, app workflow の責務が混在し、変更影響範囲が不明瞭

## スコープ

- 運用モデルの定義
- ディレクトリ責務の定義
- 禁止パターンの定義
- 設計判断・リスクの初期登録
- cutover/rollback の最低要件定義

## 非ゴール

- マニフェスト大規模移動
- CI 実装変更

## 具体タスク

1. 現行責務の棚卸し（bootstrap / platform / workloads / app delivery）
2. `automation/` と `manifests/` の責務境界を明文化
3. app delivery の新責務（infra repo と app repo）を定義
4. 旧仕様完全削除方針を確定（`user-applications` 廃止、`add-runner` 系廃止）
5. 禁止パターンを定義（例: 直接 rollout restart 依存、旧互換レイヤ長期残置）
6. bootstrap 入口の最終形を定義（root Application 1つ）
7. rollback 最低要件（旧 tag / snapshot / backup）を定義
8. `decision-log.md` に主要方針を記録
9. `risk-register.md` に初期リスクを登録
10. PH1 以降の前提条件を `roadmap.md` に反映

## 変更対象

- `tasks/roadmap.md`
- `tasks/decision-log.md`
- `tasks/risk-register.md`
- `tasks/status.md`

## 検証

1. 方針文書レビューで責務境界に矛盾がないこと
2. 既存 `make phase1..5` と PH 管理フェーズが混同しないこと
3. 「旧仕様停止または削除」ではなく「旧仕様完全削除」が定義されていること

## 完了条件

1. 目標運用モデルが文書化済み
2. 各ディレクトリの責務境界が定義済み
3. 禁止パターンが列挙済み
4. 主要リスクと対策が初期登録済み
5. 旧仕様完全削除と rollback 要件が明文化済み
