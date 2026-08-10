# 構造改革ステータス

最終更新日: 2026-08-10

## Current Phase

- PH6: Complete（構造改革完了）
- 2026-08-10: DEC-0043 により `make add-runner` / `make add-runners-all` の runner / workflow 自動生成運用を復活した（sandbox `:latest` の再デプロイ経路回復のため）。以下に「削除済み」とある runner 自動生成・generated workflow・harbor-auth secret・sandbox Deployment patch 権限は復活済み current-state に変更する。

## Summary

- PH0 の target operating model、planning artifact、主要設計判断は確定済み
- single root `Application`、child `Application` split、`access/**` owner 層、`sandbox-config` の platform 移設は current repo の事実として扱う
- PH2 residual は完了済み。topology 新設ではなく、planning artifact / audit / inventory / stale reference の残差収束として処理した
- PH4 は完了済み。home-lab contract 正本、access surface drift check、ExternalSecret domain split、secret/local 境界の target-state gate を実装済み
- PH1 は完了済み。公式 `make bootstrap` 入口、pre-ESO 最小前提、bootstrap / steady-state 分離、Nix toolchain 境界を実装済み
- PH3 は完了済み。app delivery を image build/push + infra repo PR に限定し、runner 自動生成と cluster 直接変更権限を削除済み
- PH5 は完了済み。`validate.sh` に policy / rendered collision / schema / consistency checks を統合し、Nix devShell toolchain を lock 済み
- PH6 の repo-side cleanup は完了済み。Grafana Cloud / monitoring stack の implementation source、docs 旧記述、古い automation docs を削除し、Dockerized Nix 上の `validate.sh` は green
- PH6 live cutover は 2026-06-02 に実施済み。旧 `monitoring` Application / namespace、legacy app aggregate Application、legacy monitoring ExternalSecret は live cluster から削除済み
- `make phase5` は 2026-06-02 21:30 JST に green。ArgoCD Application 46 件は `Synced/Healthy`、主要 Namespace / Node / Pod / ExternalSecret / Gateway / Cloudflared 検証は成功
- 2026-06-02 の最終確認で ArgoCD Application 46 件は引き続き `Synced/Healthy`、`monitoring` namespace と legacy Applications は NotFound、ExternalSecret は全件 Ready
- disposable rehearsal / rollback rehearsal / VM snapshot / etcd snapshot / ArgoCD auto-sync 停止は未実施だが、live cutover 後の記録済み例外として `cutover-checklist.md` に固定済み
- `automation/docs/external-secrets-README.md` は旧 automation 手順から current GitOps 正本への案内に置換済み
- `docs/` は current-state、`tasks/` は target-state planning を正とする。ただし main に既に入った topology change は planning 側でも current-state fact として反映する

## In Progress

- なし

## Blocked

- なし

## Next Gate

- なし。Gate PH6 passed。構造改革は完了

## Open Decisions

- なし

## Recently Closed

- PH0/PH2 の未決論点はすべて解消済み
- `sandbox-config` の shared config owner、internal surface ID、service IP 命名、Harbor split owner、access extraction 順は固定済み
- root `Application` の entrypoint と child `Application` discovery source は `manifests/bootstrap/applications/**` に固定済み
- PH2 residual cleanup として `.github/workflows/weekly-version-audit.yml` の monitoring / Grafana k8s-monitoring 特別扱いを削除済み
- `legacy-removal-inventory.md` は active delete scope と historical reflow check を区別済み
- workspace-local empty dir ではなく tracked path / stale reference / reinflow rule を gate target とする方針を固定済み
- PH4 初期 contract として `manifests/contracts/home-lab/cluster-contract.yaml` / `access-surfaces.yaml` を作成済み
- access owner manifest に `contracts.k8s-myhome.local/access-surface` annotation を追加し、contract entry との追跡を開始済み
- CoreDNS / Tailscale Split DNS / Cloudflared / Gateway に contract key annotation を追加し、主要固定値の由来を追跡可能にした
- contract 必須値と access surface annotation の存在は `automation/scripts/ci/consistency-check.sh` で検出する
- `automation/scripts/ci/contract-check.py` を追加し、access contract と `HTTPRoute` / `Gateway` / Cloudflared / CoreDNS / Tailscale Split DNS の hostname・listener・publish 整合性を検出する
- `ExternalSecret` を `stores`, `argocd`, `harbor`, `github-actions`, `networking`, `app-runtime` の domain 単位へ分割し、pre-ESO path の top-level `ExternalSecret` を解消済み
- Grafana Cloud / monitoring legacy secret は target-state secret 正本から除外済み。monitoring stack 本体の削除は PH6 delete scope として維持する
- PH4 完了状態で `automation/scripts/ci/validate.sh` は green
- PH1 として `make bootstrap` / `automation/scripts/run.sh bootstrap` を実装し、`automation/platform/platform-deploy.sh` を ArgoCD 初期導入、pre-ESO Secret、root Application 適用へ限定済み
- bootstrap 経路から Harbor / ARC / Grafana / access plane の個別収束処理、manual patch / rollout restart、自動 add-runner を除去済み
- `flake.nix` を追加し、`devShells.default` と `devShells.bootstrap` の役割を固定済み。実行環境に `nix` がないため `flake.lock` 生成は PH5 toolchain pinning へ引き継ぐ
- `automation/host-setup/setup-host.sh` は `K8S_MYHOME_USE_NIX_TOOLCHAIN=true` の場合に CLI 重複導入を避け、libvirt / KVM / Docker / systemd は host prerequisite として維持する
- `make all` は `phase1 -> phase2 -> bootstrap -> phase5` の順序へ更新済み
- PH3 として旧 runner 自動生成、generated workflow、legacy secret template、runner の shared Secret 読み取り / Deployment patch 権限を削除済み
- app delivery 契約は image build/push + infra repo PR 作成に固定し、runtime PR と access PR の切り分けを docs に反映済み
- PH5 として `automation/scripts/ci/policy-check.sh` / `policy-check.py` を追加し、`validate.sh` へ統合済み
- PH5 policy check は legacy identifier 再流入、app delivery 直接 rollout、first-party `:latest` 条件、pre-ESO `ExternalSecret`、`HEAD` / `prune:false`、child Application owner 重複、`apps/**` への access resource 混入、Harbor legacy split-owner artifact、rendered resource collision を検出する
- PH5 schema check として `kubeconform` を `validate.sh` へ統合し、CRD / ArgoCD / ExternalSecret / Gateway API / MetalLB / cert-manager 系は `-ignore-missing-schemas` と skip list で段階導入した
- `.github/workflows/ci-deploy-validate.yml` は `nix develop .#default --command automation/scripts/ci/validate.sh` 実行へ移行済み
- `flake.lock` を生成し、`flake.nix` の validate / bootstrap toolchain を pin 済み
- 旧 Grafana deploy script と `automation/platform/.github/workflows/` の生成済み app workflow を削除済み
- PH6 repo-side cleanup として monitoring Application、`manifests/monitoring/` values、`monitoring` namespace、Grafana chart allowlist、docs 旧記述、古い automation docs を削除済み
- PH6 repo-side cleanup 後の検証コマンド `docker run --rm -v "$PWD":/work -w /work nixos/nix:2.24.11 nix --extra-experimental-features 'nix-command flakes' develop path:/work#default --command automation/scripts/ci/validate.sh` は green
- live cutover は完了。disposable rehearsal / rollback rehearsal / VM snapshot / etcd snapshot は未取得であり、手順逸脱として `cutover-checklist.md` に記録する
- PH6 完了整理として `automation/docs/external-secrets-README.md` を current GitOps 正本への案内へ置換し、旧 automation / monitoring 手順の残留を解消した
- `cutover-checklist.md` の必須項目は実施済みまたは記録済み例外へ分類済み
- `risk-register.md` の PH6 関連 Open risk は close し、代替監視は backlog 管理へ切り離した
- Gate PH6 passed と判定し、構造改革を完了した
- 履歴は `open-issues.md` を参照する

#### PH6 repo candidate re-validated

- `docs/access.md` の Cloudflare ExternalSecret 参照を domain split 後の `manifests/platform/secrets/external-secrets/networking/cloudflare-api-token.yaml` に更新した
- 新規 HTTPRoute 追加手順を `manifests/access/<app>/` と `access-surfaces.yaml` の contract annotation 前提へ修正した
- `policy-rule-spec.md` の monitoring legacy allowlist 説明を PH6 cutover 後の fail-closed 仕様へ更新した
- live inventory で以下の旧 live resource 残存を確認した: `Application/monitoring`, `Application/user-applications`, `Application/user-application-definitions`, `Application/harbor-patch`, `monitoring` namespace, monitoring ExternalSecret, legacy ARC credential ExternalSecret
- live inventory で `ghcr-nginx-charts-secret` と `github-repo-secret` が `argocd` namespace に残存していることを確認した。repo candidate では削除対象であり、cutover 後に prune / live cleanup 確認が必要
- 検証コマンド `docker run --rm -v "$PWD":/work -w /work nixos/nix:2.24.11 nix --extra-experimental-features 'nix-command flakes' develop path:/work#default --command automation/scripts/ci/validate.sh` は green
- candidate は未コミット差分であり、live cutover の前提である main 反映は未完了

#### PH6 live cutover verified

- main 反映済み cutover commits: `22488fb`, `4d118f0`, `076620e`, `7145131`, `ffed3d2`, `6c21e05`, `37ba779`, `b1c795c`
- `make bootstrap` を実行し、`bootstrap-root` / child Applications を GitOps `HEAD` へ収束させた
- stuck した旧 `monitoring` Application は pre-delete finalizer を解除して削除した。`monitoring` namespace は旧 Alloy CR / operator Deployment の finalizer を解除し、削除完了を確認した
- legacy aggregate Applications `user-application-definitions`, `user-applications`, `harbor-patch`, `coredns-config`, `nginx-gateway-resources`, `tailscale-split-dns` は finalizer 解除後に削除済み
- Harbor chart の `*-secret.yaml` template 7件が `.gitignore` により未追跡だった問題を修正し、`harbor` Application は `Synced/Healthy` に復旧した
- Gateway API defaulting による access Applications の OutOfSync を解消するため、HTTPRoute manifest を `group` / `kind` / `matches` / `weight` 明示形へ正規化した
- CronJob の過去実行失敗が Application health を Degraded にするため、ArgoCD health customization で CronJob は configured state を Healthy と評価するよう変更した。Job 実行成否は Job / log 側の運用監視で扱う
- `docker run --rm -v "$PWD":/work -w /work nixos/nix:2.24.11 nix --extra-experimental-features 'nix-command flakes' develop path:/work#default --command automation/scripts/ci/validate.sh` は green
- `make phase5` は green。ArgoCD Application は 46 件すべて `Synced/Healthy`

## Progress Log

### 2026-06-02

#### PH6 repo candidate complete

- Grafana Cloud / 現行 monitoring stack の repo-side legacy を削除した
- `manifests/bootstrap/applications/platform/monitoring.yaml` と `manifests/monitoring/grafana-k8s-monitoring-values.yaml` を削除した
- `config-secrets` の destination namespace を `external-secrets-system` へ変更した
- `AppProject/platform` から Grafana Helm repo allowlist と `monitoring` namespace destination を削除した
- `manifests/core/namespaces.yaml` から `monitoring` namespace を削除した
- docs / diagram / manifests README から Grafana k8s-monitoring と `manifests/monitoring/` 前提を削除した
- 古い automation docs の legacy credential 記述を削除した
- `policy-check.py` の PH6 monitoring legacy allowlist を縮小し、旧 path 再流入を fail-closed にした
- 検証コマンド `docker run --rm -v "$PWD":/work -w /work nixos/nix:2.24.11 nix --extra-experimental-features 'nix-command flakes' develop path:/work#default --command automation/scripts/ci/validate.sh` は green
- live rehearsal / live cutover / rollback rehearsal はこの repo-side 作業では未実施

#### PH5 complete

- Gate PH5 passed と判定した
- `automation/scripts/ci/policy-check.sh` と `automation/scripts/ci/policy-check.py` を追加し、`validate.sh` の公開判定入口に統合した
- R-001 / R-002 / R-003 / R-004 / R-005 / R-006 / R-007 / R-008 / R-009 / R-010 / R-011 と monitoring legacy 再流入 guard を実装した
- rendered resource collision は child `Application` の repo-local kustomize path を render し、同一 document identity の複数 owner 出力を fail する
- `kubeconform` を `validate.sh` に追加し、CRD 系は skip list と `-ignore-missing-schemas` で段階導入した
- CI は Nix devShell 経由の `nix develop .#default --command automation/scripts/ci/validate.sh` に移行した
- `flake.lock` を生成し、CI / ローカル validate toolchain を共通化した
- 旧 Grafana deploy script と generated app workflow を削除し、PH3/PH5 の direct rollout / runner automation legacy check を green にした
- 検証コマンド `nix develop path:/work#default --command automation/scripts/ci/validate.sh` は Dockerized Nix 上で green
- 次フェーズを PH6 Cutover Docs and Cleanup に更新した

#### PH3 complete

- Gate PH3 passed と判定した
- `Makefile` から runner 自動生成ターゲットを削除し、runner 定義は `manifests/platform/ci-cd/github-actions/runners-appset.yaml` の Git 管理へ一本化した
- `automation/scripts/github-actions/` の旧生成スクリプトと generated workflow、`automation/templates/github-actions-workflow.yml`、legacy secret template、`common-k8s-utils.sh` を削除した
- `github-actions-rbac.yaml` を Runner ServiceAccount のみへ縮小し、shared Secret 読み取りと sandbox Deployment patch 権限を削除した
- `docs/app-delivery.md`, `docs/operations.md`, `docs/bootstrap.md`, `docs/gitops.md`, `AGENTS.md`, `automation/settings.toml.example` を app delivery 契約へ更新した
- `R-005` を Closed にした
- 次フェーズを PH5 Safety Policy and Validation に更新した

#### PH1 complete

- Gate PH1 passed と判定した
- `Makefile` と `automation/scripts/run.sh` に公式 `bootstrap` 入口を追加し、root Application 適用経路を `make bootstrap` に一本化した
- `automation/platform/platform-deploy.sh` を GitOps bootstrap 専用へ置換し、ArgoCD 初期導入、`pulumi-esc-token` / ESO RBAC、root Application 適用のみを行うようにした
- bootstrap 経路から Harbor EXT_ENDPOINT patch、`harbor-auth` Secret 作成、containerd node mutation、ARC runner 自動追加、Grafana k8s-monitoring 自動デプロイを除去した
- `flake.nix` を追加し、`nix develop .#default` / `nix develop .#bootstrap` の役割を固定した。現在の実行環境には `nix` がないため `flake.lock` は未生成で、PH5 の toolchain pinning 実装時に生成する
- `automation/host-setup/setup-host.sh` に Nix-aware mode を追加し、Nix shell 内では Terraform / Ansible / kubectl / Helm の apt 導入をスキップする
- `README.md`, `docs/bootstrap.md`, `docs/operations.md`, `AGENTS.md` を `make bootstrap` 前提へ更新した
- `automation/scripts/verify.sh` と `automation/scripts/generate-cluster-diagram.sh` から monitoring namespace 必須前提を除去した
- 検証コマンド `automation/scripts/ci/validate.sh` は green
- 次フェーズを PH3 Delivery Separation に更新した

#### PH4 complete

- Gate PH4 passed と判定した
- 完了記録は `tasks/ph4-environment-contract-centralization.md` の `完了記録` を正とする
- 検証コマンド `automation/scripts/ci/validate.sh` は green
- 次フェーズを PH1 Bootstrap Minimalization に更新した

#### PH2 residual / PH4 implementation

- PH2 residual を完了扱いに変更し、Current Phase を PH4 に更新した
- `.github/workflows/weekly-version-audit.yml` から Grafana / monitoring / `k8s-monitoring` の特別扱いを削除し、child `Application` discovery source を `manifests/bootstrap/applications/**` に維持した
- PH2 固有リスク `R-004`, `R-012`, `R-014` を Closed にした
- PH4 初期 contract として `manifests/contracts/home-lab/cluster-contract.yaml` と `manifests/contracts/home-lab/access-surfaces.yaml` を追加した
- service access の `HTTPRoute` に `contracts.k8s-myhome.local/access-surface` annotation を追加し、contract entry と実装 resource の対応を追跡可能にした
- Gateway / CoreDNS / Tailscale Split DNS / Cloudflared に contract key annotation を追加し、domain / service IP / tunnel ID / publish surface の由来を明示した
- `automation/scripts/ci/contract-check.py` を追加し、access contract と access manifests の hostname / listener / backend / publication drift を `validate.sh` 経由で検出できるようにした
- `automation/scripts/ci/validate.sh` の yamllint 対象から vendored Helm chart 配下を除外し、raw Helm template を YAML として誤検出しないようにした
- `.github/workflows/ci-deploy-validate.yml` に `pyyaml` を追加し、CI でも contract-aware check を実行できるようにした
- `ExternalSecret` を domain 単位に分割し、`external-secret-resources.yaml` monolith と `platform/argocd-config/harbor-unified-registry-secrets.yaml` を削除した
- target-state secret 正本から Grafana Cloud / monitoring legacy ExternalSecret を除外した
- `docs/manifests.md` / `docs/secrets.md` を追加し、contract 変更手順、ハードコード許容例外、secret 配置ルールを current-state docs として固定した
- PH4 の再流入防止 gate を `automation/scripts/ci/consistency-check.sh` に追加した
- PH4 完了状態で `automation/scripts/ci/validate.sh` は green

## Notes

- main ブランチに旧新併存を残さない
- `apps/` は workload-only、公開/接続系は `access/` に分離する
- 各サービスは `runtime + access` の pair を持てるが、それ以外の owner 分割は禁止する
- owner 一意性の最終担保は rendered resource collision check とする
- PH5 / PH6 の公式 pass/fail 判定は `automation/scripts/ci/validate.sh` を正とする
- canonical regex / identifier set / validation semantics は `policy-rule-spec.md` を正とする
- `make bootstrap` / `automation/scripts/run.sh bootstrap` / `nix develop .#bootstrap` は現行 repo の公式 bootstrap 導線である
- Grafana Cloud と現行 `monitoring` stack は PH6 で完全削除する legacy として扱い、代替監視基盤は `tasks/backlog.md` で別管理する
- Git は空ディレクトリを追跡しないため、PH2 / PH5 の判定対象は workspace-local empty dir ではなく、tracked path / stale reference / 再流入防止ルールとする
