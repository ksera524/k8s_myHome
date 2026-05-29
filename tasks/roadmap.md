# 構造改革ロードマップ

## 目的

- bootstrap の安定化
- GitOps 所有関係の明確化
- app delivery と infra 管理の責務分離
- 環境依存値と運用リスクの可視化・制御
- 旧仕様を main から完全削除し、再流入を防止

## フェーズ順序

`PH0 -> PH1 -> PH2 -> PH3 -> PH4 -> PH5 -> PH6`

## マイルストーン

1. M1: 改革方針確定（PH0 完了）
2. M2: bootstrap 安定化（PH1 完了）
3. M3: GitOps 所有関係正規化（PH2 完了）
4. M4: app delivery 分離（PH3 完了）
5. M5: 環境設定一元化（PH4 完了）
6. M6: 安全弁と検証強化（PH5 完了）
7. M7: 新構造への完全移行（PH6 完了）

## フェーズゲート

1. Gate A（PH0 完了条件）
   - 目標運用モデル、責務境界、禁止パターンが文書化されている
   - 「旧仕様を完全削除する」方針が明文化されている
2. Gate B（PH1 完了条件）
   - bootstrap と steady-state の責務分離が完了している
3. Gate C（PH2 完了条件）
   - Application 所有関係の重複が解消されている
   - `user-applications` / `user-application-definitions` が削除されている
4. Gate D（PH3 完了条件）
   - app deploy が GitOps commit 経由のみになっている
   - `add-runner` 系自動生成運用が削除されている
5. Gate E（PH4 完了条件）
   - 環境固有値の正本が 1 か所に定義されている
   - 非機密 contract と secret/local 設定が分離されている
6. Gate F（PH5 完了条件）
   - CI が主要禁止パターンを検出して fail できる
7. Gate G（PH6 完了条件）
   - docs と実装が一致し、旧フローが削除されている
   - main に旧仕様が残っていない

## 依存関係

- PH1 は PH0 の方針合意に依存
- PH2 は PH1 の bootstrap 分離に依存
- PH3 は PH2 の所有関係整理に依存
- PH4 は PH3 の責務分離方針に依存
- PH5 は PH1〜PH4 の新ルール確定に依存
- PH6 は PH1〜PH5 の反映完了に依存

## 進行管理ルール

- 作業ごとに `status.md` を更新し、週次で要約する
- 各 PH は「完了条件」を全件満たすまでクローズしない
- 仕様変更は `decision-log.md` へ追記
- リスク・ブロッカーは `risk-register.md` で追跡
- 例外運用は `policy-exception-register.md` で期限管理する

## cutover 原則

- main ブランチへの反映は「旧新併存なし」の単発 cutover を原則とする
- cutover 前に必ず snapshot/backup を取得する
- rollback は「旧 tag + snapshot」で即時復元できる形を維持する

## 非ゴール（今回の改革対象外）

- 新規アプリ機能開発
- 別クラウド/別リージョンへの同時展開
- 本番 SaaS レベルの多重冗長化
