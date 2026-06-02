# 旧仕様削除インベントリ

## 目的

- PH6 cutover で main から削除すべき旧仕様を一覧化する
- 削除漏れを防ぎ、完了判定を明確化する
- Secret の keep / delete / live-confirm 判定正本は `external-secret-split-plan.md` とし、本ファイルは削除対象索引と operational grep 観点を集約する
- canonical identifier set / regex 語彙は `policy-rule-spec.md` を正とし、本ファイルの grep は PH6 実施用の operational example とする

## PH6 delete scope（repo-side cleanup 済み / live 確認対象）

2026-06-02 時点で repo-side cleanup は完了済み。以下は PH6 で削除対象にした canonical scope と、live cutover 時に repo / live cluster の双方で再出現していないことを確認する対象である。

### 1) Grafana Cloud / 現行 monitoring stack

- `manifests/bootstrap/applications/platform/monitoring.yaml`
- `manifests/bootstrap/applications/platform/kustomization.yaml` の `monitoring.yaml` entry
- `manifests/bootstrap/applications/platform/config-secrets.yaml` の `destination.namespace: monitoring`
- `manifests/monitoring/grafana-k8s-monitoring-values.yaml`
- `manifests/platform/argocd-config/argocd-projects.yaml` の `https://grafana.github.io/helm-charts` allowlist
- `manifests/platform/argocd-config/argocd-projects.yaml` の `namespace: monitoring` destination
- `manifests/platform/secrets/external-secrets/kustomization.yaml` の Grafana Cloud 関連参照
- `manifests/platform/secrets/external-secrets/grafana-cloud-external-secret.yaml`
- `manifests/platform/secrets/external-secrets/grafana-monitoring-external-secret.yaml`
- `automation/platform/platform-deploy.sh` の Grafana k8s-monitoring 自動デプロイ導線
- `automation/platform/deploy-grafana-monitoring.sh`
- `automation/platform/deploy-grafana-with-secret.sh`
- `automation/platform/deploy-grafana-monitoring-simple.sh`
- `automation/settings.toml.example` の `enable_monitoring`
- `.github/workflows/weekly-version-audit.yml` の Grafana k8s-monitoring 監査ロジック
- `docs/gitops-design.md` の monitoring stack 前提記述
- `docs/diagrams/app-of-apps-sync-wave.md` の Monitoring wave 記述
- `docs/applications.md` の monitoring stack 記述
- `docs/operations-guide.md` の monitoring 前提記述
- `docs/kubernetes-architecture.md` の Grafana Cloud 送信先記述
- `automation/scripts/verify.sh` の `monitoring` namespace 必須前提
- `automation/scripts/generate-cluster-diagram.sh` の `monitoring` namespace 前提

### 2) `add-runner` 自動生成系

- `automation/scripts/github-actions/add-runner.sh`
- `automation/scripts/github-actions/add-runners-bulk.sh`
- `automation/scripts/github-actions/.github/workflows/`
- `automation/platform/.github/workflows/`
- `automation/templates/github-actions-workflow.yml`
- `automation/scripts/github-actions/setup-arc.sh`
- `automation/scripts/common-k8s-utils.sh`
- `automation/platform/platform-deploy.sh` の `arc_repositories` 解析と `add-runner.sh` 呼び出し
- `Makefile` の `add-runner` / `add-runners-all` ターゲット
- `automation/settings.toml*` の `arc_repositories` 運用
- `manifests/platform/ci-cd/github-actions/kustomization.yaml` の `add-runner.sh` 前提コメント
- `AGENTS.md` の runner 追加手順
- `docs/quickstart.md` の runner 追加手順
- `docs/gitops-design.md` / `docs/operations-guide.md` / `docs/setup-guide.md` / `docs/quickstart.md` の該当手順

### 3) legacy / duplicate credential Secret と stale template

- `manifests/platform/argocd-config/harbor-unified-registry-secrets.yaml` の旧 pre-ESO 配置
- `manifests/platform/secrets/external-secrets/external-secret-resources.yaml` 内の `harbor-auth-secret`
- `manifests/platform/secrets/external-secrets/external-secret-resources.yaml` 内の `harbor-registry-secret`
- `manifests/platform/secrets/external-secrets/external-secret-resources.yaml` 内の `github-auth-secret`
- `automation/scripts/common-k8s-utils.sh` の `harbor-auth` / `github-auth` 既定値
- `automation/scripts/github-actions/setup-arc.sh` の `harbor-auth` 手動生成
- `automation/platform/platform-deploy.sh` の legacy credential 参照
- `automation/templates/external-secrets/harbor-external-secret.yaml`
- `automation/templates/external-secrets/harbor-registry-external-secret.yaml`
- `automation/templates/external-secrets/slack-external-secret.yaml`
- `automation/templates/platform/argocd-github-oauth-secret.yaml`

### 4) live確認付き削除候補

- `manifests/platform/secrets/external-secrets/external-secret-resources.yaml` 内の `ghcr-nginx-charts-secret`
- `manifests/platform/secrets/external-secrets/external-secret-resources.yaml` 内の `github-repo-secret`
- `harbor-registry` の `default` / `argocd` namespace copy
- 上記は repo 内参照だけで未使用断定せず、PH6 cutover 前に live cluster / ArgoCD inventory で consumer 実在を確認して keep / delete を決める

## historical legacy（current repo では解消済み、再流入だけ防ぐもの）

- `user-applications`
- `user-application-definitions`
- `harbor-patch`
- `argocd-external-app.yaml`
- `rustfs-external-app.yaml`
- `cloudflared-app.yaml`
- `argocd-external`
- `rustfs-external`
- `manifests/infrastructure/networking/nginx-gateway-fabric/gateway/`
- `manifests/infrastructure/networking/coredns/`
- `manifests/infrastructure/networking/tailscale-split-dns/`
- `manifests/infrastructure/gitops/harbor/harbor-routes.yaml`
- `manifests/infrastructure/gitops/harbor/harbor-image-cleanup-cronjob.yaml`

上記は current repo では implementation source から外れているため、PH6 では「active delete」ではなく grep / policy / checklist による再流入防止対象として扱う。

## dead path / reservation policy

- Git は空ディレクトリを追跡しないため、workspace-local empty dir 自体は完了判定に使わない
- target state では `manifests/apps/argocd/**`, `manifests/apps/rustfs/**`, `manifests/apps/cloudflared/**` のような retired access path に tracked file を再作成しない
- `manifests/apps/harbor`, `manifests/apps/monitoring`, `manifests/apps/postgresql`, `manifests/apps/slack`, `manifests/apps/user-up` などの historical name を reservation 用 path として Git 正本に復活させない

## 検証コマンド（PH6）

```bash
grep -R -n -E 'user-applications|user-application-definitions' manifests automation docs .github AGENTS.md README.md Makefile
grep -R -n -E 'add-runner\.sh|add-runners-bulk\.sh|add-runners-all|arc_repositories' manifests automation docs .github AGENTS.md README.md Makefile
grep -R -n -E 'harbor-patch|argocd-external-app\.yaml|rustfs-external-app\.yaml|cloudflared-app\.yaml|argocd-external|rustfs-external' manifests automation docs .github AGENTS.md README.md Makefile
grep -R -n -E 'k8s-monitoring|grafana-cloud-monitoring|grafana-cloud-credentials|promtail-grafana-cloud-config|grafana\.github\.io/helm-charts|grafana\.net|deploy-grafana-monitoring|deploy-grafana-with-secret|deploy-grafana-monitoring-simple|namespace:[[:space:]]*monitoring' manifests automation docs .github AGENTS.md README.md Makefile
grep -R -n -E 'harbor-auth|harbor-auth-secret|github-auth|github-auth-secret|harbor-registry-secret' manifests automation docs .github AGENTS.md README.md Makefile
grep -R -n -E 'kind:[[:space:]]*(HTTPRoute|Gateway|Ingress|ClientSettingsPolicy|BackendTLSPolicy|ReferenceGrant)' manifests/apps
if [ -d automation/scripts/github-actions ]; then grep -R -n -E 'kubectl rollout restart' automation/scripts/github-actions; fi
if [ -d automation/platform/.github/workflows ]; then grep -R -n -E 'kubectl rollout restart' automation/platform/.github/workflows; fi
grep -R -n -E 'kubectl rollout restart' .github/workflows
grep -R -n -E 'harbor\.qroksera\.com/.+:latest' manifests/apps
test ! -e manifests/bootstrap/applications/platform/monitoring.yaml
! grep -q -E 'namespace:[[:space:]]*monitoring' manifests/bootstrap/applications/platform/config-secrets.yaml
test ! -e manifests/platform/argocd-config/harbor-unified-registry-secrets.yaml
test ! -e automation/templates/external-secrets/harbor-external-secret.yaml
test ! -e automation/templates/external-secrets/harbor-registry-external-secret.yaml
test ! -e automation/templates/external-secrets/slack-external-secret.yaml
test ! -e automation/templates/platform/argocd-github-oauth-secret.yaml
automation/scripts/ci/validate.sh
```

上記は最終的に `policy-rule-spec.md` に従う状態を目標とする（`tasks/` は計画文書のため対象外）。
workspace-local empty dir は Git 正本ではないため、最終判定は retired path への tracked file 再流入と `automation/scripts/ci/validate.sh` の結果を正とする。
`harbor.qroksera.com/sandbox/*:latest` は `sandbox` namespace に限り条件付き許容のため、最終判定は `automation/scripts/ci/validate.sh`（内部で `policy-check.sh` を含む）を正とする。
`ghcr-nginx-charts-secret`、`github-repo-secret`、`harbor-registry` の `default` / `argocd` copy は live 確認付き削除候補のため、repo grep 0 件だけでは完了判定にしない。
