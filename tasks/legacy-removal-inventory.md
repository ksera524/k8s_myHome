# 旧仕様削除インベントリ

## 目的

- PH6 cutover で main から削除すべき旧仕様を一覧化する
- 削除漏れを防ぎ、完了判定を明確化する
- Secret の keep / delete / live-confirm 判定正本は `external-secret-split-plan.md` とし、本ファイルは削除対象索引と operational grep 観点を集約する
- canonical identifier set / regex 語彙は `policy-rule-spec.md` を正とし、本ファイルの grep は PH6 実施用の operational example とする

## 削除対象（確定）

### 1) `user-applications` 系

- `manifests/bootstrap/app-of-apps.yaml` 内の `user-applications`
- `manifests/bootstrap/app-of-apps.yaml` 内の `user-application-definitions`
- `automation/platform/platform-deploy.sh` の `user-applications` 参照
- `automation/scripts/verify.sh` の `user-applications` 参照
- `docs/setup-guide.md` の `user-applications` 同期手順
- `docs/gitops-design.md` の `user-applications` 前提記述
- `docs/external-access-guide.md` の `user-application-definitions` refresh 手順
- `docs/diagrams/app-of-apps-sync-wave.md` の `User App Definitions` / `User Applications` wave 記述

### 2) access legacy（`apps/` 配下や旧配置に残る公開/接続系）

- `manifests/bootstrap/app-of-apps.yaml` 内の `harbor-patch`
- `manifests/bootstrap/app-of-apps.yaml` 内 `harbor-patch` の `prune:false`
- `manifests/bootstrap/app-of-apps.yaml` 内 `harbor-patch` の `ignoreDifferences`（`ConfigMap/harbor-core`, `Deployment/harbor-core`）
- `manifests/bootstrap/applications/user-apps/argocd-external-app.yaml`
- `manifests/bootstrap/applications/user-apps/rustfs-external-app.yaml`
- `manifests/bootstrap/applications/user-apps/cloudflared-app.yaml`
- `manifests/apps/argocd/`
- `manifests/apps/rustfs/`
- `manifests/apps/cloudflared/`
- `manifests/apps/blog/` など app 配下に残る `HTTPRoute` の旧配置
- `manifests/apps/cooklog/` など app 配下に残る内部公開 route / access 定義の旧配置
- `manifests/infrastructure/networking/nginx-gateway-fabric/gateway/` にある shared listener / Gateway resource の現行配置
- `manifests/infrastructure/gitops/harbor/harbor-routes.yaml` の旧配置
- `manifests/infrastructure/gitops/harbor/harbor-image-cleanup-cronjob.yaml` の旧配置
- `manifests/infrastructure/gitops/harbor/kustomization.yaml` の steady-state 入口
- `manifests/infrastructure/networking/coredns/coredns-configmap.yaml` に分散した公開ホスト定義の旧配置
- `manifests/infrastructure/networking/tailscale-split-dns/manifest.yaml` に分散した access 定義の旧配置
- `.github/workflows/weekly-version-audit.yml` の `manifests/bootstrap/applications/user-apps/rustfs-app.yaml` hardcode
- `.github/workflows/weekly-version-audit.yml` の `manifests/apps/cloudflared/manifest.yaml` hardcode
- `docs/applications.md` の `argocd-external`, `rustfs-external`, `cloudflared` 前提記述
- `docs/diagrams/app-of-apps-sync-wave.md` の `harborPatch`, `argocd-external`, `rustfs-external`, `cloudflared` 記述

### 3) `add-runner` 自動生成系

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

### 4) 旧 app delivery 経路

- app delivery workflow からの `kubectl` 直接操作
- app delivery workflow からの `kubectl rollout restart` 依存
- `sandbox` namespace 外の first-party workload における `:latest` 運用

### 5) Grafana Cloud / 現行 monitoring stack

- `manifests/bootstrap/app-of-apps.yaml` 内の `monitoring` Application
- `manifests/monitoring/grafana-k8s-monitoring-values.yaml`
- `manifests/platform/argocd-config/argocd-projects.yaml` の `https://grafana.github.io/helm-charts` 許可
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

### 6) legacy / duplicate credential Secret と stale template

- `manifests/platform/argocd-config/harbor-unified-registry-secrets.yaml` の旧配置
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

### 7) live確認付き削除候補

- `manifests/platform/secrets/external-secrets/external-secret-resources.yaml` 内の `ghcr-nginx-charts-secret`
- `manifests/platform/secrets/external-secrets/external-secret-resources.yaml` 内の `github-repo-secret`
- `harbor-registry` の `default` / `argocd` namespace copy
- 上記は repo 内参照だけで未使用断定せず、PH6 cutover 前に live cluster / ArgoCD inventory で consumer 実在を確認して keep / delete を決める

### 8) dead path / reservation policy

- `manifests/apps/harbor`, `manifests/apps/monitoring`, `manifests/apps/postgresql`, `manifests/apps/slack`, `manifests/apps/user-up` は current branch では既に存在しない
- PH6 では上記のような dead path を reservation 用に再作成しないこと自体を target state とする

## 検証コマンド（PH6）

```bash
grep -R -n -E 'user-applications|user-application-definitions' manifests automation docs .github AGENTS.md README.md Makefile
grep -R -n -E 'add-runner\.sh|add-runners-bulk\.sh|add-runners-all|arc_repositories' manifests automation docs .github AGENTS.md README.md Makefile
grep -R -n -E 'harbor-patch|argocd-external-app\.yaml|rustfs-external-app\.yaml|cloudflared-app\.yaml|manifests/bootstrap/applications/user-apps/rustfs-app\.yaml|manifests/apps/cloudflared/manifest\.yaml|argocd-external|rustfs-external' manifests automation docs .github AGENTS.md README.md Makefile
grep -R -n -E 'k8s-monitoring|grafana-cloud-monitoring|grafana-cloud-credentials|promtail-grafana-cloud-config|grafana\.github\.io/helm-charts|grafana\.net|deploy-grafana-monitoring|deploy-grafana-with-secret|deploy-grafana-monitoring-simple' manifests automation docs .github AGENTS.md README.md Makefile
grep -R -n -E 'harbor-auth|harbor-auth-secret|github-auth|github-auth-secret|harbor-registry-secret' manifests automation docs .github AGENTS.md README.md Makefile
grep -R -n -E 'kind:[[:space:]]*(HTTPRoute|Gateway|Ingress|ClientSettingsPolicy|BackendTLSPolicy|ReferenceGrant)' manifests/apps
if [ -d automation/scripts/github-actions ]; then grep -R -n -E 'kubectl rollout restart' automation/scripts/github-actions; fi
if [ -d automation/platform/.github/workflows ]; then grep -R -n -E 'kubectl rollout restart' automation/platform/.github/workflows; fi
grep -R -n -E 'kubectl rollout restart' .github/workflows
grep -R -n -E 'harbor\.qroksera\.com/.+:latest' manifests/apps
test ! -e manifests/platform/argocd-config/harbor-unified-registry-secrets.yaml
test ! -e automation/templates/external-secrets/harbor-external-secret.yaml
test ! -e automation/templates/external-secrets/harbor-registry-external-secret.yaml
test ! -e automation/templates/external-secrets/slack-external-secret.yaml
test ! -e automation/templates/platform/argocd-github-oauth-secret.yaml
automation/scripts/ci/validate.sh
```

上記は最終的に `policy-rule-spec.md` に従う状態を目標とする（`tasks/` は計画文書のため対象外）。
削除済みディレクトリは「存在しないこと自体を pass」と扱う。
`harbor.qroksera.com/sandbox/*:latest` は `sandbox` namespace に限り条件付き許容のため、最終判定は `automation/scripts/ci/validate.sh`（内部で `policy-check.sh` を含む）を正とする。
`ghcr-nginx-charts-secret`、`github-repo-secret`、`harbor-registry` の `default` / `argocd` copy は live 確認付き削除候補のため、repo grep 0 件だけでは完了判定にしない。
