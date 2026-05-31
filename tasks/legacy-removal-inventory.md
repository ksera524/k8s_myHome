# 旧仕様削除インベントリ

## 目的

- PH6 cutover で main から削除すべき旧仕様を一覧化する
- 削除漏れを防ぎ、完了判定を明確化する

## 削除対象（確定）

### 1) `user-applications` 系

- `manifests/bootstrap/app-of-apps.yaml` 内の `user-applications`
- `manifests/bootstrap/app-of-apps.yaml` 内の `user-application-definitions`
- `automation/platform/platform-deploy.sh` の `user-applications` 参照
- `automation/scripts/verify.sh` の `user-applications` 参照
- `docs/setup-guide.md` の `user-applications` 同期手順
- `docs/gitops-design.md` の `user-applications` 前提記述
- `docs/external-access-guide.md` の `user-application-definitions` refresh 手順

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
- `manifests/infrastructure/networking/nginx-gateway-fabric/gateway/` の旧配置
- `manifests/infrastructure/gitops/harbor/harbor-routes.yaml` の旧配置
- `manifests/infrastructure/gitops/harbor/harbor-image-cleanup-cronjob.yaml` の旧配置
- `manifests/infrastructure/gitops/harbor/kustomization.yaml` の steady-state 入口
- `manifests/infrastructure/networking/coredns/coredns-configmap.yaml` に分散した公開ホスト定義の旧配置
- `manifests/infrastructure/networking/tailscale-split-dns/manifest.yaml` に分散した access 定義の旧配置

### 6) empty dir / dead path

- `manifests/apps/harbor`
- `manifests/apps/monitoring`
- `manifests/apps/postgresql`
- `manifests/apps/slack`
- `manifests/apps/user-up`
- reservation 目的で empty dir を残さないこと自体を target state とする

### 3) `add-runner` 自動生成系

- `automation/scripts/github-actions/add-runner.sh`
- `automation/scripts/github-actions/add-runners-bulk.sh`
- `automation/templates/github-actions-workflow.yml`
- `automation/platform/platform-deploy.sh` の `arc_repositories` 解析と `add-runner.sh` 呼び出し
- `Makefile` の `add-runner` / `add-runners-all` ターゲット
- `automation/settings.toml*` の `arc_repositories` 運用
- `manifests/platform/ci-cd/github-actions/kustomization.yaml` の `add-runner.sh` 前提コメント
- `AGENTS.md` の runner 追加手順
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
- `.github/workflows/weekly-version-audit.yml` の Grafana k8s-monitoring 監査ロジック
- `docs/gitops-design.md` の monitoring stack 前提記述
- `docs/diagrams/app-of-apps-sync-wave.md` の Monitoring wave 記述
- `docs/applications.md` の monitoring stack 記述
- `docs/kubernetes-architecture.md` の Grafana Cloud 送信先記述
- `automation/scripts/verify.sh` の `monitoring` namespace 必須前提
- `automation/scripts/generate-cluster-diagram.sh` の `monitoring` namespace 前提

### 6) legacy / duplicate credential Secret と stale template

- `manifests/platform/argocd-config/harbor-unified-registry-secrets.yaml` の旧配置
- `manifests/platform/secrets/external-secrets/external-secret-resources.yaml` 内の `harbor-auth-secret`
- `manifests/platform/secrets/external-secrets/external-secret-resources.yaml` 内の `harbor-registry-secret`
- `manifests/platform/secrets/external-secrets/external-secret-resources.yaml` 内の `github-auth-secret`
- `manifests/platform/secrets/external-secrets/external-secret-resources.yaml` 内の `github-repo-secret`
- `automation/templates/external-secrets/harbor-external-secret.yaml`
- `automation/templates/external-secrets/harbor-registry-external-secret.yaml`
- `automation/templates/external-secrets/slack-external-secret.yaml`
- `automation/templates/platform/argocd-github-oauth-secret.yaml`

### 7) live確認付き削除候補

- `manifests/platform/secrets/external-secrets/external-secret-resources.yaml` 内の `ghcr-nginx-charts-secret`
- `harbor-registry` の `default` / `argocd` namespace copy
- 上記は repo 内参照だけで未使用断定せず、PH6 cutover 前に live cluster / ArgoCD inventory で consumer 実在を確認して keep / delete を決める

## 検証コマンド（PH6）

```bash
grep -R -n -E 'user-applications|user-application-definitions' manifests automation docs .github AGENTS.md README.md Makefile
grep -R -n -E 'add-runner\.sh|add-runners-bulk\.sh|add-runners-all|arc_repositories' manifests automation docs .github AGENTS.md README.md Makefile
grep -R -n -E 'harbor-patch|argocd-external-app\.yaml|rustfs-external-app\.yaml|cloudflared-app\.yaml' manifests automation docs .github AGENTS.md README.md Makefile
grep -R -n -E 'grafana-cloud-monitoring|grafana-cloud-credentials|promtail-grafana-cloud-config|grafana-k8s-monitoring|chart:[[:space:]]*k8s-monitoring|grafana\.github\.io/helm-charts|grafana\.net|deploy-grafana-monitoring|deploy-grafana-with-secret|deploy-grafana-monitoring-simple' manifests automation docs .github AGENTS.md README.md Makefile
grep -R -n -E 'harbor-auth|github-auth|harbor-registry-secret|github-repo-secret' manifests automation docs .github AGENTS.md README.md Makefile
grep -R -n -E 'kind:[[:space:]]*(HTTPRoute|Gateway|Ingress|ClientSettingsPolicy|BackendTLSPolicy|ReferenceGrant)' manifests/apps
if [ -d automation/scripts/github-actions ]; then grep -R -n -E 'kubectl rollout restart' automation/scripts/github-actions; fi
grep -R -n -E 'kubectl rollout restart' .github/workflows
grep -R -n -E 'harbor\.qroksera\.com/.+:latest' manifests/apps
test ! -e manifests/platform/argocd-config/harbor-unified-registry-secrets.yaml
test ! -e automation/templates/external-secrets/harbor-external-secret.yaml
test ! -e automation/templates/external-secrets/harbor-registry-external-secret.yaml
test ! -e automation/templates/external-secrets/slack-external-secret.yaml
test ! -e automation/templates/platform/argocd-github-oauth-secret.yaml
automation/scripts/ci/validate.sh
```

上記は最終的に policy に従う状態を目標とする（`tasks/` は計画文書のため対象外）。
削除済みディレクトリは「存在しないこと自体を pass」と扱う。
`harbor.qroksera.com/sandbox/*:latest` は `sandbox` namespace に限り条件付き許容のため、最終判定は `automation/scripts/ci/validate.sh`（内部で `policy-check.sh` を含む）を正とする。
`ghcr-nginx-charts-secret` と `harbor-registry` の `default` / `argocd` copy は live 確認付き削除候補のため、repo grep 0 件だけでは完了判定にしない。
