# ポリシー判定仕様（CI向け）

## 目的

- PH5 の CI ルールを機械判定可能な形で定義する
- 「禁止」「条件付き許容」「例外」の優先順位を固定する
- runtime / access 分離後の再流入と collision を検出可能にする

## 判定優先順位

1. ルールIDごとに「禁止」「条件付き許容」「例外可否」を確定する
2. 条件付き許容ルールは、定義された条件を先に評価する
3. 条件を満たさず、かつそのルールが例外を許可する場合のみ `policy-exception-register.md` を参照する
4. 例外不可ルールは台帳登録があっても fail とする
5. manifest-aware ルールは「top-level manifest document」または render 後 document を正とし、コメントや `ignoreDifferences` の文字列一致だけで違反扱いしない

## 判定対象ディレクトリ

- `manifests/`
- `automation/`
- `docs/`
- `.github/`
- `AGENTS.md`
- `README.md`
- `Makefile`

`tasks/` は計画文書のため対象外。

## 正本コマンド

- PH5 完了時点の公開判定入口は `automation/scripts/ci/validate.sh` のみとする
- `automation/scripts/ci/policy-check.sh` は `validate.sh` から呼ばれる内部実装とし、ローカルデバッグ目的の単独実行は許容しても、CI / rehearsal / cutover の公式 pass/fail 判定には使わない
- PH6 の rehearsal / cutover 判定は `validate.sh` の成功を正とし、`policy-check.sh` / `kubeconform` はその内部要素として扱う

## 導入段階

- PH5 の完了判定は current main ではなく、branch / rehearsal 上の target-state もしくは single cutover candidate commit を対象に行う
- `R-001`, `R-002`, `R-003`, `R-007`, `R-008`, `R-009`, `R-010`, `R-011` は target-state branch / candidate commit では fail-closed とする
- PH6 cutover 前の current main では、legacy が残る間は上記ルールを advisory 扱いとしてよく、required status への昇格は legacy 削除差分を含む candidate commit の反映と同時に行う

## 用語定義

- `bootstrap scope`: `manifests/bootstrap/**` と、bootstrap script が ArgoCD steady-state 前に直接適用するリソース
- `bootstrap 直下 Application`: `manifests/bootstrap/**` 配下の ArgoCD `Application`
- `first-party image`: `harbor.qroksera.com/` で始まる image
- `first-party workload`: `manifests/apps/**` 配下の top-level workload manifest document で、`Deployment`, `StatefulSet`, `DaemonSet`, `Job`, `CronJob`, `Pod` のいずれかを kind に持ち、`first-party image` を参照するもの
- `pre-ESO scope`: `ExternalSecret` controller が Ready になる前に適用される scope。初期実装では少なくとも `manifests/bootstrap/**` と `manifests/platform/argocd-config/**` を含む
- `allowlisted prune:false`: 以下の `document identity + field_path` の組み合わせのみを指す
- `app child Application`: `manifests/bootstrap/applications/user-apps/*.yaml` 配下の ArgoCD `Application`
- `access child Application`: `manifests/bootstrap/applications/access/*.yaml` 配下の ArgoCD `Application`
- `document identity`: 原則 `kind + metadata.namespace + metadata.name`。namespace がない場合は `kind + metadata.name` を用いる
- `rendered first-party workload`: raw manifest または app 専用 values / template から最終的に render された namespaced workload で、`first-party image` を参照するもの
- `access resource`: `HTTPRoute`, `Gateway`, `Ingress`, `ClientSettingsPolicy`, `BackendTLSPolicy`, `ReferenceGrant` など、公開/接続面を構成する top-level resource。初期実装では必要に応じて allowlist / denylist を明示する
- `runtime/access pair`: 同一サービスに対して `manifests/apps/<app>` と `manifests/access/<service>` が対応する所有モデル
- `access surface`: hostname / listener / backend / tunnel / DNS publish を束ねた公開契約単位。正本は `manifests/contracts/home-lab/access-surfaces.yaml`
- `owner-local non-secret config`: 特定 runtime owner だけが使う非機密設定。正本は `manifests/apps/<app>/` または対応する runtime owner path 配下とし、contract / shared-config / secret へ昇格させない
- `runtime-local endpoint`: owner 内の automation / CronJob / maintenance job が使う in-cluster Service 到達先。公開契約ではなく、owner local configuration として扱う

| Document | Field |
|---|---|
| `Application/argocd/argocd-projects` | `spec.syncPolicy.automated.prune` |
| `Application/argocd/argocd-core` | `spec.syncPolicy.automated.prune` |
| `Application/argocd/arc-controller` | `spec.syncPolicy.automated.prune` |

`Application/argocd/harbor-patch` の `prune:false` は current main にのみ残る legacy transitional state として扱い、target-state branch / candidate commit の allowlist には含めない。

## Canonical Identifier Sets

以下の identifier set は `tasks/` 内の phase 文書、checklist、inventory で共通に参照する canonical set とする。重複列挙が必要な場合でも、本節の語彙を増減させず参照する。

### legacy app aggregation identifiers

- `user-applications`
- `user-application-definitions`

### runner automation legacy identifiers

- `add-runner.sh`
- `add-runners-bulk.sh`
- `add-runners-all`
- `arc_repositories`
- generated workflow artifact: `automation/platform/.github/workflows/**`
- generated workflow artifact: `automation/scripts/github-actions/.github/workflows/**`

### Grafana / monitoring legacy identifiers

- `k8s-monitoring`
- `grafana-cloud-monitoring`
- `grafana-cloud-credentials`
- `promtail-grafana-cloud-config`
- `grafana.github.io/helm-charts`
- `grafana.net`
- `deploy-grafana-monitoring`
- `deploy-grafana-with-secret`
- `deploy-grafana-monitoring-simple`

### fixed-delete credential identifiers

- `harbor-auth`
- `harbor-auth-secret`
- `github-auth`
- `github-auth-secret`
- `harbor-registry-secret`

### PH6 grep path set

- `manifests/`
- `automation/`
- `docs/`
- `.github/`
- `AGENTS.md`
- `README.md`
- `Makefile`
- `kubectl rollout restart` の grep は `automation/platform/.github/workflows/` と `automation/scripts/github-actions/.github/workflows/` も明示対象に含める

## ルール定義

### R-001: legacy app 集約経路の禁止

- パターン: `user-applications|user-application-definitions`
- 期待: 0 件
- 例外可否: 不可

### R-002: runner 自動生成運用と generated workflow legacy の禁止

- パターン: `add-runner\.sh|add-runners-bulk\.sh|add-runners-all|arc_repositories`
- 対象追加制約: `automation/platform/.github/workflows/` と `automation/scripts/github-actions/.github/workflows/` に add-runner 由来 artifact を残さない
- 期待: 0 件
- 例外可否: 不可

### R-003: app delivery 経路での直接 rollout 禁止

- パターン: `kubectl rollout restart`
- 対象追加制約: `.github/workflows/`, `automation/scripts/github-actions/`, `automation/platform/.github/workflows/`, `automation/scripts/github-actions/.github/workflows/` 配下
- 期待: 0 件
- 例外可否: 不可

### R-004: first-party workload の `:latest` 制御

- 対象: `rendered first-party workload` の image
- 条件付き許容:
  - raw manifest の場合: path が `manifests/apps/**` 配下であり、同一 top-level workload manifest document の `metadata.namespace` が `sandbox` で、`containers` / `initContainers` / `jobTemplate.spec.template.spec.containers` のいずれかで `harbor.qroksera.com/sandbox/*:latest` を参照していること
  - app 専用 values / template の場合: 最終 render 後の workload namespace が `sandbox` で、image が `harbor.qroksera.com/sandbox/*:latest` であること
- 禁止: 上記条件を満たさない first-party workload の `:latest`
- 例外可否: 不可
- 実装メモ:
  - line regex だけでは判定できないため、manifest document 単位または render 出力単位で namespace / kind / image を同時評価する
  - Helm / app 専用 values を使う app は child Application の render 出力または同等 template 出力を正として判定する

### R-005: pre-ESO `ExternalSecret` 禁止

- 条件付き許容:
  - top-level `ExternalSecret` は `manifests/platform/secrets/external-secrets/**` 配下にのみ存在してよい
- 禁止:
  - `manifests/bootstrap/**` 配下の top-level `ExternalSecret`
  - `manifests/platform/argocd-config/**` 配下の top-level `ExternalSecret`
  - root Application の sync order 上で `external-secrets-operator` より前に適用される path 配下の top-level `ExternalSecret`
- 期待: 0 件
- 例外可否: 不可
- 実装メモ: `ignoreDifferences` 内の `kind: ExternalSecret` 文字列や CRD schema 内の記述は違反に含めない

### R-006: `HEAD` / `prune:false` の制御

- `HEAD`:
  - 条件付き許容: `manifests/bootstrap/**` 配下の Git source Application
  - 例外可: bootstrap 以外で一時運用が必要な場合のみ `policy-exception-register.md` に登録
- `prune:false`:
  - 条件付き許容: `allowlisted prune:false`
  - 例外可: allowlist 外で一時運用が必要な場合のみ `policy-exception-register.md` に登録
- 期待: 条件外使用は例外なしか fail

### R-007: app owner 重複の禁止

- 目的: legacy 集約 owner への回帰と、per-app child Application の owner 二重化を防ぐ
- 禁止:
  - `manifests/bootstrap/**` 配下の top-level `Application` が `spec.source.path: manifests/apps` を持つこと
  - `manifests/bootstrap/**` 配下の top-level `Application` が `spec.source.path: manifests/bootstrap/applications/user-apps` を持つこと
  - `app child Application` 間で `metadata.name` が重複すること
  - `app child Application` 間で `spec.source.path` が重複すること
  - `app child Application` の `spec.source.path` が `manifests/apps/<app>` 形式でないこと
- 条件付き許容: なし
- 例外可否: 不可
- 実装メモ:
  - 初期実装では「汎用 resource 重複検出」ではなく、bootstrap app owner 構造に限定した structural rule とする
  - `argocd-projects` と `argocd-core` のように同一 directory を参照しても source 設定が異なるケースは、このルールの違反対象にしない

### R-008: `manifests/apps/**` 配下への access resource 配置禁止

- 対象:
  - `manifests/apps/**` 配下の top-level manifest document
  - `manifests/apps/cloudflared/**`, `manifests/apps/argocd/**`, `manifests/apps/rustfs/**` の path 自体
- 禁止:
  - kind が `HTTPRoute`, `Gateway`, `Ingress`, `ClientSettingsPolicy`, `BackendTLSPolicy`, `ReferenceGrant` の document
  - `manifests/apps/cloudflared/**`, `manifests/apps/argocd/**`, `manifests/apps/rustfs/**` に file が存在すること
- 条件付き許容: なし
- 例外可否: 不可
- 実装メモ:
  - 初期実装は kind ベース denylist と path ベースチェックの組み合わせでよい
  - `CoreDNS`, `Tailscale Split DNS`, Harbor routes のような access-only document は target path を `manifests/access/**` とし、semantic owner 名ではなく path/identity で判定する
  - app workload 内部の環境変数文字列やコメント中の hostname は、このルール単独では違反にしない

### R-009: rendered resource collision の禁止

- 対象: child Application ごとに render した manifest document
- 禁止:
  - 同一 `document identity` を複数 child Application が同時に出力すること
  - 同一 `document identity` の namespaced resource が runtime owner と access owner の両方から出力されること
- 条件付き許容: なし
- 例外可否: 不可
- 実装メモ:
  - 初期実装では `Application` ごとの render 出力を比較し、差分元 child Application 名もレポートする
  - cluster-scoped resource も `document identity` で比較する

### R-010: access surface 契約逸脱の禁止

- 対象:
  - `manifests/access/**`
  - `Cloudflared`, `CoreDNS`, `Tailscale Split DNS` の hostname / publication 定義
  - `manifests/contracts/home-lab/access-surfaces.yaml`
- 禁止:
  - contract 未登録 hostname を公開/接続系 manifest で使うこと
  - contract に定義された backend / listener / publish 方式と実装が矛盾すること
  - `manifests/apps/**` 配下に hostname-bearing access surface を定義すること
- 条件付き許容: なし
- 例外可否: 不可
- 実装メモ:
  - 初期実装では `access-surfaces.yaml` と access owner path の相互参照を行い、必要なら許容対象ファイルを allowlist 化する
  - `Cloudflared` / `CoreDNS` / `Tailscale Split DNS` の ConfigMap は正規化済みの hostname 一覧へ落として比較する

### R-011: Harbor legacy split-owner artifact の禁止

- 対象:
  - `manifests/bootstrap/**`
  - `manifests/infrastructure/gitops/harbor/**`
- 禁止:
  - `document identity` が `Application/argocd/harbor-patch` の top-level `Application`
  - `manifests/infrastructure/gitops/harbor/harbor-routes.yaml` が steady-state path に存在すること
  - `manifests/infrastructure/gitops/harbor/harbor-image-cleanup-cronjob.yaml` が steady-state path に存在すること
  - `Application/argocd/harbor-patch` の `ignoreDifferences` による `harbor-core` 例外が残ること
- 条件付き許容: なし
- 例外可否: 不可
- 実装メモ:
  - `node-mutations/**` は opt-in operational overlay であり、このルール単独では違反にしない
  - path 存在チェックと document identity / field path チェックを組み合わせる

## CI 連携方針

- `automation/scripts/ci/validate.sh` を唯一の公開入口として維持する
- `automation/scripts/ci/policy-check.sh` を `validate.sh` から呼び出す
- `automation/scripts/ci/` にルール検出スクリプトを実装する
- ルール違反時は対象ファイルとルールIDを出力して fail する
- 例外対象は `policy-exception-register.md` を参照して判定する
- `R-004`, `R-005`, `R-009`, `R-010` は manifest-aware check とし、単純 grep のみで完結させない
- `R-006` は document identity / field path allowlist と例外台帳の両方を参照する
- `R-007` は bootstrap Application manifest を対象に structural check として実装する
- `R-008` は path / kind denylist ベースの再流入防止ルールとして実装する
- `R-011` は Harbor legacy path / Application identity / stale `ignoreDifferences` の複合チェックとして実装する

## 例外IDの紐付け仕様

- 例外の判定単位は `rule_id + file_path + document identity + field_path` で行う
- CI 側は少なくとも以下を一致条件として扱う
  - 例外ID
  - 関連ルールID（R-00x）
  - 対象ファイル
  - document identity（例: `Application/argocd/argocd-core`）
  - field path（例: `spec.syncPolicy.automated.prune`）
  - 期限
- 期限切れ例外は自動で fail 扱いにする
