# 構造改革タスク管理

この `tasks/` ディレクトリは、k8s_myHome の**構造改革プログラム**を管理するための専用領域です。

## 目的

- 改革のゴール、順序、完了条件を明確化する
- 局所最適ではなく、全体最適の観点で進行管理する
- 設計判断・リスク・進捗を分散させず一元管理する
- 旧仕様を main から完全削除する移行を、安全に完遂する

## 役割分担

- `tasks/`: 構造改革プロジェクトの計画と進行管理
- `docs/tasks/`: 個別運用テーマや作業メモ

## ファイル一覧

- `roadmap.md`: 全体ロードマップ（正本）
- `status.md`: 現在の進捗・ブロッカー・次アクション
- `decision-log.md`: 重要設計判断の履歴
- `risk-register.md`: リスク台帳
- `policy-exception-register.md`: ポリシー例外台帳（期限付き）
- `policy-rule-spec.md`: CI 検証の判定仕様
- `legacy-removal-inventory.md`: 旧仕様の削除対象一覧
- `external-secret-split-plan.md`: `manifests/platform/secrets/external-secrets/` の target-state 分割案
- `cutover-checklist.md`: cutover 実施チェックリスト
- `backlog.md`: PH6 後の残課題一覧
- `ph0-*.md` 〜 `ph6-*.md`: フェーズ別タスクと完了条件

## 運用ルール

1. 全体順序の変更は必ず `roadmap.md` に反映する
2. `status.md` は**作業ごと**に更新し、週次で要約を追記する
3. 大きな方針変更は `decision-log.md` に記録する
4. 新規リスクは `risk-register.md` に登録する（owner 必須）
5. 例外運用は `policy-exception-register.md` に登録し、期限を持たせる
6. 各 PH は「完了条件」を満たした時点で完了扱いにする

## フェーズ定義

- `PH0`: Target Operating Model 合意（削除方針固定）
- `PH1`: Bootstrap 最小化
- `PH2`: GitOps トポロジ正規化（owner 一意化）
- `PH3`: Delivery 分離（PR/commit 経由へ統一）
- `PH4`: 環境契約一元化（非機密 contract と secret 分離）
- `PH5`: 安全弁・検証強化（再流入防止）
- `PH6`: Cutover・旧仕様完全削除・ドキュメント整合

## 注意

- 既存 `make phase1` 〜 `make phase5`（構築フェーズ）とは別物です
- 本ディレクトリの `PHx` は**構造改革の管理フェーズ**です
- 本改革では main ブランチに旧新併存期間を残しません
