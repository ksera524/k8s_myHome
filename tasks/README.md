# 構造改革タスク管理

この `tasks/` ディレクトリは、k8s_myHome の**構造改革プログラム**を管理するための専用領域です。

## 目的

- 改革のゴール、順序、完了条件を明確化する
- 局所最適ではなく、全体最適の観点で進行管理する
- 設計判断・リスク・進捗を分散させず一元管理する
- 旧仕様を main から完全削除する移行を、安全に完遂する

## 役割分担

- `tasks/`: 構造改革プロジェクトの target-state 設計と進行管理
- `docs/`: 現行 live repo の構成・手順・運用ドキュメント
- `docs/tasks/`: 個別運用テーマや作業メモ

## 正本マトリクス

| 概念 | planning 正本 | implementation 正本 | 補足 |
|---|---|---|---|
| 現行の実行手順 / live 構成 | - | `Makefile`, `automation/scripts/run.sh`, `manifests/`, `docs/` | `tasks/` は current-state の正本ではない |
| 改革フェーズ順序 / Gate 要約 | `roadmap.md` | - | program-level の順序と依存だけを持つ |
| 各 PH の詳細スコープ / 完了条件 | `ph0-*.md` 〜 `ph6-*.md` | - | 個別フェーズの作業範囲と Done 条件 |
| 進捗 / ブロッカー / 未決論点 | `status.md` | - | active な未決論点は本ファイルの `Open Decisions` だけで管理する |
| target owner / target path の設計 | `component-ownership-matrix.md` | 対応する `manifests/bootstrap/**`, `manifests/apps/**`, `manifests/access/**`, `manifests/platform/**` | `tasks/` 側は planning canonical。実装後の live ownership は manifest 実体を正とする |
| target access surface の設計 | `access-surface-matrix.md` | `manifests/contracts/home-lab/access-surfaces.yaml`, `manifests/access/**` | hostname / listener / backend / publish の planning canonical |
| target contract 棚卸し | `environment-contract-inventory.md` | `manifests/contracts/home-lab/cluster-contract.yaml` と関連 manifest | 非機密 contract / shared-config / owner-local の planning canonical |
| cutover 手順 / PH6 pass-fail | `cutover-checklist.md` | - | rehearsal / live / rollback の詳細手順と判定正本 |
| ExternalSecret keep / delete / live-confirm | `external-secret-split-plan.md` | `manifests/platform/secrets/external-secrets/**` | secret 判定の planning canonical。`legacy-removal-inventory.md` は索引 |
| legacy 削除対象の索引 / operational grep | `legacy-removal-inventory.md` | candidate commit, repo grep, `automation/scripts/ci/validate.sh` | canonical identifier set は `policy-rule-spec.md` を参照する |
| policy / identifier set / 判定語彙 | `policy-rule-spec.md` | `automation/scripts/ci/validate.sh`, `automation/scripts/ci/policy-check.sh` | canonical regex / rule semantics の正本 |
| 設計判断の理由 | `decision-log.md` | - | why の正本。owner/path 一覧の正本ではない |
| 解消済み論点の履歴 | `open-issues.md` | - | archive のみ。active tracker ではない |

## ファイル一覧

### active 文書

- `roadmap.md`: 全体ロードマップ（program-level の正本）
- `status.md`: 現在の進捗・ブロッカー・active な未決論点
- `decision-log.md`: 重要設計判断の履歴
- `risk-register.md`: リスク台帳
- `policy-rule-spec.md`: CI 検証の判定仕様と canonical identifier set
- `policy-exception-register.md`: ポリシー例外台帳（期限付き）
- `legacy-removal-inventory.md`: 旧仕様の削除対象一覧と operational grep 観点
- `external-secret-split-plan.md`: `manifests/platform/secrets/external-secrets/` の target-state 分割案
- `cutover-checklist.md`: cutover 実施チェックリスト
- `component-ownership-matrix.md`: target owner / path の planning canonical
- `access-surface-matrix.md`: target access surface の planning canonical
- `environment-contract-inventory.md`: target contract 棚卸しの planning canonical
- `ph0-*.md` 〜 `ph6-*.md`: フェーズ別タスクと完了条件

### 履歴 / 補助文書

- `open-issues.md`: 解消済み論点の履歴アーカイブ
- `backlog.md`: PH6 後の残課題一覧

## 運用ルール

1. 全体順序の変更は必ず `roadmap.md` に反映する
2. `status.md` は**作業ごと**に更新し、active な未決論点は `Open Decisions` だけで管理する
3. 大きな方針変更は `decision-log.md` に記録する
4. 新規リスクは `risk-register.md` に登録する（owner 必須）
5. 例外運用は `policy-exception-register.md` に登録し、期限を持たせる
6. 各 PH は「完了条件」を満たした時点で完了扱いにする
7. canonical regex / identifier set / rule semantics は `policy-rule-spec.md` に集約し、他文書へ重複定義しない

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
- `docs/` は current-state、`tasks/` は target-state planning を正とします
- current-state と target-state が衝突した場合、現行実装の説明は `Makefile` / `automation/scripts/run.sh` / `manifests/` / `docs/` を優先し、改革後の将来像は `tasks/` を参照します
