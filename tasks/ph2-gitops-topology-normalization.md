# PH2: GitOps Topology Residual Cleanup and Access Ownership Synchronization

## 目的

- main に既に入った GitOps topology change を current-state の事実として固定する
- planning artifact、audit、inventory、stale reference の残差を収束させる
- PH4 / PH1 / PH5 へ進む前に topology 関連の認識ずれをなくす

## 背景

- single root `Application`、child `Application` split、`access/**` への owner 分離は current repo に既に反映されている
- 一方で `tasks/` の planning artifact、inventory、cutover 前提、週次 audit には旧 topology 前提が残っている
- 実装済み事項と未実装事項が PH2 に混在すると、PH4 / PH1 / PH5 の依存判断が鈍る

## スコープ

- current repo に合わせた planning artifact の同期
- topology-aware automation / audit の residual cleanup
- dead path / stale reference / tracked placeholder の整理
- monitoring legacy を PH6 delete scope として inventory 化する追跡
- PH5 policy 実装へ渡す暫定チェック手順の定義

## 非ゴール

- single root `Application` や `access/**` 分離の再実装
- bootstrap 入口の再設計（PH1 で扱う）
- monitoring legacy の実削除（PH6 で扱う）
- app repo CI / delivery 契約の変更（PH3 で扱う）

## current-state 固定事項

1. access owner は `service access` と `shared access plane` の 2 層で固定する
2. `service access` owner は `argocd-access`, `harbor-access`, `rustfs-access`, `blog-access`, `cooklog-access`, `api-hub-access`, `hitomi-upload-viewer-access` とする
3. `shared access plane` owner は `gateway-shared`, `cloudflared`, `dns-core`, `dns-tailscale` とする
4. `Gateway` resource / listener 基盤は `gateway-shared` が `manifests/access/gateway/` を所有する
5. `Cloudflared`, `CoreDNS`, `Tailscale Split DNS` は shared access plane owner に集約する
6. child `Application` の粒度は `1 owner / 1 file / 1 path` に固定する
7. remote chart を含む runtime owner でも child `Application` の例外を作らず、repo-local wrapper path を正本にする
8. `rustfs` の runtime owner は `platform` に固定し、repo-local wrapper path は `manifests/platform/rustfs/` とする
9. ArgoCD `AppProject` は `core`, `infrastructure`, `platform`, `access`, `apps` の 5 系統を canonical とし、`access` child `Application` は専用 project に固定する
10. single root `Application` は `manifests/bootstrap/app-of-apps.yaml` 1 件に固定し、`spec.source.path` は `manifests/bootstrap/applications/` の top-level `kustomization.yaml` を entrypoint とする
11. version audit / topology-aware automation の child `Application` discovery source は `manifests/bootstrap/applications/**` に固定し、root `Application` や planning docs を discovery 入力にしない
12. `docs/` は current-state、`tasks/` は target-state planning を正とし、main に既に入った topology change は planning 側でも current-state fact として同期する
13. Git が追跡しない workspace-local empty dir は PH2 gate target に含めず、tracked path / stale reference / placeholder file / policy rule を正とする

## residual cleanup 順序

1. planning artifact を current repo に同期する
   - `component-ownership-matrix.md`, `access-surface-matrix.md`, `environment-contract-inventory.md`, `legacy-removal-inventory.md`, `status.md`
2. audit / inventory の stale reference を更新する
   - `weekly-version-audit.yml`, cutover inventory, policy input を current topology に揃える
3. dead path / reinflow 語彙を整理する
   - 既に main から消えた legacy と、PH6 でまだ消すべき legacy を分離する
4. monitoring legacy を PH6 delete scope として隔離する
   - PH2 は inventory と追跡に留め、削除そのものは PH6 に寄せる
5. PH5 へ暫定チェックを handoff する
   - structural rule / reinflow check / collision check の実装入力を固定する

## sync wave 原則

1. `infra controllers`
2. `gateway-shared`
3. `runtime owners`
4. `service access owners`
5. `shared publishers`

## 具体タスク

1. `tasks/` の planning artifact を current repo の child `Application` 名、path、owner、current location に同期する
2. main に既に入った root / child split と `access/**` 分離を、PH2 の未完了タスクではなく current-state fact として扱う
3. 全 child `Application` の `metadata.name` / `spec.source.path` 一意性を確認し、PH5 structural rule の入力へ落とす
4. `.github/workflows/weekly-version-audit.yml` の child `Application` discovery を維持したまま、monitoring 特別扱いと stale hardcode を除去する
5. current-state を説明する docs のうち、すでに main に入った topology change を説明する箇所だけを同期し、target-only 記述は PH6 まで `tasks/` に留める
6. `legacy-removal-inventory.md` を current repo 基準へ更新し、すでに main から消えた legacy は「reflow check」へ、まだ live path に残る legacy は「active delete scope」へ分離する
7. `manifests/apps/**` の retired access path については tracked file の再流入禁止を正とし、workspace-local empty dir を gate target にしない方針を明文化する
8. Harbor runtime/access split は current repo fact として matrix / inventory / cutover 文書へ反映し、`node-mutations/` は opt-in overlay として扱う
9. monitoring legacy は `manifests/bootstrap/applications/platform/monitoring.yaml`、`config-secrets` の `destination.namespace: monitoring`、Grafana 監査ロジック等の current live path を inventory 化し、PH6 delete scope として固定する
10. PH2 判定用の暫定チェック手順を定義し、恒久ルールの実装を PH5 へ引き継ぐ

## 変更対象

- `tasks/status.md`
- `tasks/component-ownership-matrix.md`
- `tasks/access-surface-matrix.md`
- `tasks/environment-contract-inventory.md`
- `tasks/legacy-removal-inventory.md`
- `tasks/policy-rule-spec.md`
- `tasks/ph6-cutover-docs-and-cleanup.md`
- `tasks/cutover-checklist.md`
- `.github/workflows/weekly-version-audit.yml`
- `automation/scripts/ci/`
- current-state を説明する `docs/` の該当箇所

## 検証

1. 全 child `Application` の `metadata.name` と `spec.source.path` が一意であること
2. `apps/**` workload と `access/**` 公開/接続系の current topology が planning artifact に一致していること
3. `service access` と `shared access plane` の owner 境界、および sync wave 原則が planning artifact と manifest で一致していること
4. Harbor の runtime/access split と `sandbox-config` の shared config owner が current repo どおりに planning artifact へ反映されていること
5. `weekly-version-audit` 相当の対象列挙が `manifests/bootstrap/applications/**` だけで成立し、root `Application` や monitoring 特別扱いに依存しないこと
6. `legacy-removal-inventory.md` が「active delete scope」と「historical reflow check」を区別して current repo を説明できること
7. current-state docs と target-state planning の境界が崩れていないこと
8. workspace-local empty dir ではなく tracked path / stale reference / reinflow rule を gate target として説明できること

## 完了条件

1. planning artifact が current repo の topology を正しく反映している
2. legacy 集約 owner は implementation path から除去済みで、全 child `Application` の一意性が確認済みである
3. `apps/**` workload と `access/**` 公開/接続系の責務分離が current-state fact として固定されている
4. `access` child `Application` 群の責務と配置先が、`service access` と `shared access plane` の 2 層で定義済みである
5. `weekly-version-audit` / inventory / cutover 文書の child `Application` discovery source が current topology に追従している
6. Harbor の runtime/access/optional ops 境界が repo-local wrapper + `harbor-access` + opt-in overlay の形で planning artifact に反映済みである
7. monitoring legacy が PH2 blocker ではなく PH6 delete scope として切り分け済みである
8. dead path / stale reference / reinflow check の語彙が整理され、workspace-local empty dir を完了条件に含めていない
9. 暫定チェック手順が定義済みで、恒久ルールの実装が PH5 へ引き継がれている
