# 設計判断ログ

## 使い方

- 重要判断ごとに 1 エントリ追加
- 変更理由・影響・代替案を残す
- 後から覆した場合も履歴を消さず追記する

## Entries

### DEC-0001: 構造改革フェーズ管理を `tasks/` に集約

- 日付: 2026-05-29
- 状態: accepted
- 背景: 改革タスクが docs/運用メモに分散し、全体進行が追いにくい
- 判断: `tasks/` を構造改革専用として新設し、roadmap/status/PH ドキュメントを集約
- 影響: 進行管理の正本が明確化。運用メモは `docs/tasks/` に分離維持
- 代替案: 既存 `docs/tasks/` に統合（不採用: 運用テーマとの混在が増えるため）

### DEC-0002: 構造改革は `PH0..PH6` で管理

- 日付: 2026-05-29
- 状態: accepted
- 背景: 既存 `make phase1..5` と改革工程の名前衝突を避けたい
- 判断: 改革管理フェーズを `PH0..PH6` に固定
- 影響: 実行フェーズ（make）と管理フェーズ（改革）を明確に区別できる
- 代替案: 既存 phase 名の再利用（不採用: 誤解と運用事故のリスクが高い）

### DEC-0003: 旧仕様は最終的に完全削除し、main に旧新併存を残さない

- 日付: 2026-05-29
- 状態: accepted
- 背景: 互換レイヤを残す運用は責務境界を曖昧化し、事故調査を困難にする
- 判断: cutover 時点で旧仕様を削除し、main には新仕様のみを残す
- 影響: 移行時の停止時間は増えるが、運用複雑性を恒久的に削減できる
- 代替案: 段階併存（不採用: 旧仕様再流入と運用分岐のリスクが高い）

### DEC-0004: `user-applications` / `user-application-definitions` は廃止する

- 日付: 2026-05-29
- 状態: accepted
- 背景: apps の owner が二重化し、どこを正本に見るべきか不明瞭だった
- 判断: apps の owner は root Application 配下の child Application 群へ一本化する
- 影響: bootstrap・verify・audit・docs の参照先更新が必要になる
- 代替案: 集約 Application 継続（不採用: 所有重複が残る）

### DEC-0005: app delivery は PR/commit 経由のみとし、cluster 直接変更を禁止する

- 日付: 2026-05-29
- 状態: accepted
- 背景: runner/workflow からの `kubectl` 操作は責務逸脱と監査困難を生む
- 判断: app delivery は「image push -> infra repo PR」で完結させる
- 影響: `add-runner` 系と workflow 自動生成は削除対象になる
- 代替案: runner 経由の直接 rollout（不採用: 責務境界に反する）

### DEC-0006: 環境依存値は「非機密 contract」と「secret/local 設定」に分離する

- 日付: 2026-05-29
- 状態: accepted
- 背景: `settings.toml` と manifests 双方へのハードコードがドリフトを招いていた
- 判断: 非機密値は Git 管理 contract に集約し、秘密値は local/ESO に限定する
- 影響: manifests の参照方式（values/patch/replacements）を再設計する必要がある
- 代替案: 現行混在維持（不採用: 変更漏れリスクが高い）

### DEC-0007: ポリシー違反は例外台帳なしに許可しない

- 日付: 2026-05-29
- 状態: accepted
- 背景: `HEAD` / `latest` / `prune:false` は一律禁止できないが、無秩序許容も危険
- 判断: 例外は `policy-exception-register.md` に owner/期限付きで登録する
- 影響: CI で「禁止」「条件付き」「例外」の3区分運用が必要になる
- 代替案: 口頭合意（不採用: 継続運用で崩壊する）
