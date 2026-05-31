# 構造改革ロードマップ

## 目的

- bootstrap の安定化
- GitOps 所有関係の明確化
- app workload と公開/接続系の責務分離
- 環境依存値と access surface の正本一元化
- app delivery と infra 管理の責務分離
- 新規 PC でのローカル operator toolchain 再現性確立
- Grafana Cloud と現行 monitoring stack を main から完全削除し、代替監視は backlog へ分離
- 旧仕様を main から完全削除し、再流入を防止

## フェーズ順序

`PH0 -> PH2 -> PH4 -> PH1 -> PH3 -> PH5 -> PH6`

## マイルストーン

1. M1: 改革方針と taxonomy 確定（PH0 完了）
2. M2: GitOps topology 正規化と access 抽出（PH2 完了）
3. M3: 環境契約 / access 契約一元化（PH4 完了）
4. M4: target topology 追従 bootstrap 確立（PH1 完了）
5. M5: delivery separation 完了（PH3 完了）
6. M6: 安全弁と検証強化（PH5 完了）
7. M7: 新構造への完全移行（PH6 完了）

## この文書の位置付け

- 本書は構造改革プログラム全体の順序、依存、Gate 要約の正本とする
- 各 PH の詳細スコープと完了条件は `ph0-*.md` 〜 `ph6-*.md` を正とする
- PH6 rehearsal / live cutover / rollback の詳細手順と pass-fail 判定は `cutover-checklist.md` を正とする
- `component-ownership-matrix.md`, `access-surface-matrix.md`, `environment-contract-inventory.md` は planning canonical とし、実装後の live 正本は対応する `manifests/**` / contract file を正とする
- `make bootstrap` / `automation/scripts/run.sh bootstrap` / `nix develop .#bootstrap` など PH1 実装後の target-state 名称は、現行 live repo の即時実行手順ではない

## フェーズゲート

1. Gate PH0（PH0 完了条件）
   - 目標運用モデル、責務境界、禁止パターンが文書化されている
   - `apps/` は workload-only、`access/` は公開/接続系の正本という taxonomy が固定されている
   - `runtime + access` pair モデルと split-owner 例外条件が定義されている
   - `component-ownership-matrix.md`、`access-surface-matrix.md`、`environment-contract-inventory.md` が planning artifact として作成済みである
   - 「旧仕様を完全削除する」方針が明文化されている
2. Gate PH2（PH2 完了条件）
   - legacy 集約 owner が除去され、app child Application の owner 重複が解消されている
   - `user-applications` / `user-application-definitions` の代替 owner と削除差分が PH6 cutover 入力として準備済みである
   - `apps/**` から公開/接続系 resource を排除する target topology が確定し、`access/**` への収束先が定義済みである
   - `access` owner が `service access` と `shared access plane` の 2 層に整理され、`Gateway` resource / listener 基盤の owner が `gateway-shared` に固定されている
   - child Application が `1 Application / 1 file / 1 owner` で差分レビュー可能になっている
   - remote chart を含む runtime owner でも `1 owner / 1 path` 原則が維持され、Harbor は repo-local wrapper path に収束している
   - empty dir / dead path が reservation として残らない方針が確定している
3. Gate PH4（PH4 完了条件）
   - 非機密 environment contract と access contract の正本が 1 か所に定義されている
   - hostname / LB IP / StorageClass / NFS など主要値と、そこから導出される access URL / host alias の根拠が contract から追跡可能である
   - runtime-local endpoint（例: Harbor cleanup CronJob の in-cluster Service 到達先）は access contract と切り分けられ、owner local configuration として説明できる
   - 非機密 contract と secret/local 設定が分離されている
   - Grafana Cloud endpoint / token / ExternalSecret が target-state の contract / secret 正本から除去準備済みである
4. Gate PH1（PH1 完了条件）
   - bootstrap と steady-state の責務分離が完了している
   - bootstrap は target topology / contract へ追従し、root Application 適用と pre-ESO 最小前提に責務が限定されている
   - bootstrap が access plane の収束ロジックや child owner 判断を持たないことが文書化されている
   - 公式 bootstrap 入口が `make bootstrap`（実体: `automation/scripts/run.sh bootstrap`）に固定されている
   - `make bootstrap` は GitOps bootstrap 専用入口であり、fresh cluster では `make phase1 -> make phase2 -> make bootstrap`、PH6 cutover では既存 cluster に対して `make bootstrap` のみを使うことが文書化されている
   - fresh cluster の標準完了順序 `make phase1 -> make phase2 -> make bootstrap -> make phase5` が文書化されている
   - fresh cluster 前提のローカル toolchain が `nix develop .#bootstrap` で再現できる
   - `nix develop .#bootstrap` はローカル operator toolchain shell、`make bootstrap` は GitOps bootstrap 入口であり、役割差分が文書化されている
5. Gate PH3（PH3 完了条件）
   - app deploy が GitOps commit 経由のみになっている
   - runtime 変更と access 変更の正規変更経路が分離され、PR 単位が明確化されている
   - `sandbox` namespace に限る `:latest` 条件付き許容ルールが固定されている
   - `add-runner` 系自動生成運用の置換と削除差分が PH6 cutover 入力として準備済みである
6. Gate PH5（PH5 完了条件）
   - branch / rehearsal 上の target-state で `automation/scripts/ci/validate.sh` が主要禁止パターンを検出して fail できる
   - `apps/**` への access resource 混入、hostname/publication 定義の逸脱、rendered resource collision を検出して fail できる
   - Grafana / monitoring legacy の canonical identifier set と fixed-delete credential identifier set が `policy-rule-spec.md` に定義され、再流入を検出して fail できる
   - `validate.sh` 実行依存が `flake.nix` / `flake.lock` で pin され、CI とローカルで共通 toolchain を使える
7. Gate PH6（PH6 完了条件）
   - docs と実装が一致し、旧フローが削除されている
   - `automation/scripts/ci/validate.sh`（内部で `policy-check.sh` を含む）が green である
   - main に旧仕様が残っていない
   - `policy-rule-spec.md` で定義した Grafana / monitoring legacy identifier set が main に残っていない
   - runtime/access pair と access surface の最終構成が docs / checklist / verify 手順に反映されている

## 依存関係

- PH2 は PH0 の taxonomy / owner ルール合意に依存
- PH4 は PH2 の target topology と access 抽出先定義に依存
- PH1 は PH2 / PH4 の target topology / contract 確定に依存
- PH3 は PH2 / PH4 の runtime/access 境界と contract 確定に依存
- PH5 は PH0〜PH4 の新ルール確定に依存
- PH6 は PH1〜PH5 の反映完了に依存

## 進行管理ルール

- 作業ごとに `status.md` を更新し、週次で要約する
- 各 PH は「完了条件」を全件満たすまでクローズしない
- 仕様変更は `decision-log.md` へ追記
- リスク・ブロッカーは `risk-register.md` で追跡
- 例外運用は `policy-exception-register.md` で期限管理する
- 未決論点は `status.md` の `Open Decisions` で owner / 期限付き管理し、解消済み論点の履歴は `open-issues.md` に残す
- PH1〜PH5 の完了は branch/rehearsal 上の新構造準備完了を含み、main からの旧仕様完全削除は PH6 で確定させる
- `component-ownership-matrix.md`、`access-surface-matrix.md`、`environment-contract-inventory.md` を planning canonical として維持し、implementation source が追従した後も差分説明用 artifact として扱う

## cutover 原則

- main ブランチへの反映は「旧新併存なし」の単発 cutover を原則とする
- `make bootstrap` / `automation/scripts/run.sh bootstrap` は PH1 実装後の target-state alias を指し、詳細な役割境界は DEC-0019 と `ph1-bootstrap-minimalization.md` を正とする
- rehearsal / live cutover / rollback の標準順序、証跡、合格条件は `cutover-checklist.md` を正とする
- legacy 削除系ルール（`R-001`, `R-002`, `R-003`, `R-007` 以降の access / collision ルールを含む）の required 化タイミングは `policy-rule-spec.md` を正とする
- rehearsal 環境を用意できない場合は PH6 Go 判定を出さない
- cutover 前に最低でも VM snapshot と etcd snapshot を取得する
- `rebuildable-stateful` と判断した workload は clean rebuild を許容する。初期対象は Harbor と RustFS とし、delete scope は `cutover-checklist.md` を正とする
- rollback は「旧 tag + snapshot」で即時復元できる形を維持し、発動基準と authority は `cutover-checklist.md` の表で固定する

## 非ゴール（今回の改革対象外）

- 新規アプリ機能開発
- 別クラウド/別リージョンへの同時展開
- 本番 SaaS レベルの多重冗長化
