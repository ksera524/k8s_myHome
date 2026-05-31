# PH0: Target Operating Model

## 目的

- 構造改革の最終形と責務境界を合意し、以降の実装判断をブレさせない
- main に旧新併存を残さず、旧仕様を最終的に完全削除する方針を固定する
- `apps` と `access` の責務を分離し、二重管理の起点を先に潰す

## 背景

- `automation/`, `manifests/`, app workflow の責務が混在し、変更影響範囲が不明瞭
- workload 本体と公開/接続系が同じ owner から見え、どこを正本としてレビューすべきか揺れている

## 正本: Target Operating Model

### ディレクトリ責務

| 領域 | 正本パス | Owner | 正規変更経路 | 備考 |
|---|---|---|---|---|
| bootstrap root | `manifests/bootstrap/app-of-apps.yaml` | gitops / platform | bootstrap script から最小限 `kubectl apply` | root Application は 1 件のみ |
| child Application 定義 | `manifests/bootstrap/applications/**/*.yaml` | gitops | infra repo PR / merge -> ArgoCD sync | `1 Application / 1 file / 1 owner` |
| app workload 実体 | `manifests/apps/<app>/` | app owner + gitops review | image push -> infra repo PR -> merge -> ArgoCD sync | workload-only。app 固有の非機密設定は owner-local configuration としてこの path に置く。`user-applications` 集約は禁止 |
| access 実体 | `manifests/access/<service>/` | platform / network / gitops | infra repo PR / merge -> ArgoCD sync | `HTTPRoute`, `Cloudflared`, DNS 公開面など |
| platform / infrastructure | `manifests/platform/`, `manifests/infrastructure/`, `manifests/core/` | platform / infra | infra repo PR / merge -> ArgoCD sync | steady-state の正本 |
| 非機密 contract | `manifests/contracts/home-lab/cluster-contract.yaml`, `manifests/contracts/home-lab/access-surfaces.yaml` と配下 fragment | infra / network | infra repo PR / merge | infra 基盤値と access surface のみ。runtime-local/shared app endpoint は含めない |
| shared app config | `manifests/platform/shared-config/**` | platform | infra repo PR / merge -> ArgoCD sync | 複数 workload が共有する非機密設定。access surface ではない endpoint を含む |
| secret / local 設定 | `automation/settings.toml` と ESO の参照元 | secret owner / local operator | local edit または ESO 側変更 | Git には秘密値本文を置かない |
| bootstrap / 運用スクリプト | `automation/` | infra / platform | ローカル実行のみ | steady-state patch / restart の正本にしない |
| ドキュメント | `README.md`, `AGENTS.md`, `docs/`, `tasks/` | docs / 各ドメイン owner | PR で更新 | 実装変更と同時に更新 |

現行の `monitoring` Application、`grafana/k8s-monitoring` values、Grafana Cloud endpoint / token / ExternalSecret、`deploy-grafana-*` スクリプトは target operating model の正本に含めず、PH6 で完全削除する。代替監視基盤の導入は今回の改革スコープ外として `tasks/backlog.md` で管理する。

PH6 では monitoring legacy 削除後の最低 cutover 観測面は `tasks/cutover-checklist.md` を正本として固定する。

### 設計原則

1. `apps/` は workload-only とし、公開/接続系 resource を置かない
2. `access/` は公開/接続系の正本とし、hostname / publication の責務を集約する
3. 各サービスは `runtime + access` の pair を持てるが、それ以外の owner 分割は禁止する
4. owner 一意性は `AppProject destination` だけでなく、rendered resource collision check で担保する
5. root Application は 1 件のみとし、集約 owner へ戻らない
6. ArgoCD `AppProject` は `core`, `infrastructure`, `platform`, `access`, `apps` の 5 系統を canonical とし、`access` は専用 project で管理する
7. app 固有の非機密設定は runtime owner path の owner-local configuration に置き、複数 workload で共有される非機密設定だけを `manifests/platform/shared-config/**` へ昇格させる
8. runtime-local endpoint は access surface と分離し、contract へ昇格させず owner local configuration として扱う
9. 例外は `decision-log.md` と `policy-exception-register.md` に明示的に記録する

### 正規変更経路

1. クラスタ最終状態の変更は `manifests/` を正本とし、ArgoCD で反映する
2. app release は「image build/push -> infra repo PR -> review/merge -> ArgoCD sync」で完結させる
3. access surface の変更は `manifests/access/**` と `manifests/contracts/home-lab/access-surfaces.yaml` を正本に反映する
4. bootstrap は `Makefile` / `automation/scripts/run.sh` から最小限の前提作成と root Application 適用だけを行う
5. secret は `automation/settings.toml` と ESO の参照元に分離し、manifest へ秘密値を直書きしない
6. app 固有の非機密設定は runtime owner path に置き、複数 workload で共有する非機密設定だけを `manifests/platform/shared-config/**` に集約する
7. service 間 URL や internal endpoint は shared-config または access surface 導出で説明し、cluster contract の独立 key にしない

### 禁止経路

- app delivery workflow / runner からの `kubectl apply`, `kubectl patch`, `kubectl rollout restart`
- `automation/` を steady-state の正本として使う手動 patch / restart 常態化
- `user-applications` / `user-application-definitions` のような集約 owner への回帰
- `apps/` 配下へ `HTTPRoute`, `Ingress`, `Gateway`, `ClientSettingsPolicy`, `Cloudflared`, DNS 公開設定などの公開/接続系 resource を置くこと
- `AppProject destination` のみを根拠に owner 一意性を主張すること
- `add-runner` 系スクリプトや `arc_repositories` による infra repo 側の workflow / runner 自動生成
- Grafana Cloud 向け endpoint / token / Helm chart / bootstrap script を steady-state の正本として残置すること
- main に旧新フローを併存させたまま長期運用すること

## スコープ

- 運用モデルの定義
- ディレクトリ責務と taxonomy の定義
- `runtime + access` pair モデルの定義
- 禁止パターンの定義
- 設計判断・リスクの初期登録
- planning artifact の初期作成
- cutover/rollback の最低要件定義

## 非ゴール

- マニフェスト大規模移動
- CI 実装変更
- 代替監視基盤の新規導入

## 具体タスク

1. 現行責務の棚卸し（bootstrap / platform / workloads / access / app delivery）
2. `automation/` と `manifests/` の責務境界を明文化
3. `core / infrastructure / platform / access / apps` の taxonomy を確定
4. `apps/` workload-only ルールと禁止 kind / 禁止 resource を定義
5. `runtime + access` pair モデルと split-owner 例外条件を定義
6. `component-ownership-matrix.md` を作成し、主要コンポーネントの current / target owner を記録
7. `access-surface-matrix.md` を作成し、hostname / listener / DNS / tunnel / backend の関係を記録
8. `environment-contract-inventory.md` を作成し、主要固定値の current location と target contract ref を記録
9. app delivery の新責務（infra repo と app repo）を定義
10. 旧仕様完全削除方針を確定（`user-applications` 廃止、`add-runner` 系廃止、monitoring legacy 廃止）
11. 禁止パターンを定義（例: 直接 rollout restart 依存、旧互換レイヤ長期残置、`apps/` への access resource 混在）
12. bootstrap 入口の最終形を定義（root Application 1 つ）
13. rollback 最低要件（旧 tag / snapshot / backup）を定義
14. `decision-log.md` に主要方針を記録
15. `risk-register.md` に初期リスクを登録
16. PH1 以降の前提条件を `roadmap.md` に反映

## 変更対象

- `tasks/roadmap.md`
- `tasks/decision-log.md`
- `tasks/risk-register.md`
- `tasks/status.md`
- `tasks/component-ownership-matrix.md`
- `tasks/access-surface-matrix.md`
- `tasks/environment-contract-inventory.md`

## 検証

1. 方針文書レビューで責務境界に矛盾がないこと
2. 既存 `make phase1..5` と PH 管理フェーズが混同しないこと
3. 「旧仕様停止または削除」ではなく「旧仕様完全削除」が定義されていること
4. `apps/` と `access/` の責務が衝突していないこと
5. Grafana Cloud と現行 monitoring stack が target state の正本に含まれていないこと
6. `access` 専用 `AppProject` と shared app config の責務が target model 上で定義済みであること

## 完了条件

1. 目標運用モデルが文書化済み
2. 各ディレクトリの責務境界が定義済み
3. 禁止パターンが列挙済み
4. 主要リスクと対策が初期登録済み
5. 旧仕様完全削除と rollback 要件が明文化済み
6. `access` ドメインの責務が定義済み
7. `apps/` 禁止 kind / 禁止 resource が列挙済み
8. `runtime + access` pair モデルが明文化済み
9. planning artifact 3 点が作成済み
10. cutover 最低観測面が monitoring legacy 非依存で定義済み
