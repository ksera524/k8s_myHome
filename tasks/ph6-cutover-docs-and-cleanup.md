# PH6: Cutover, Docs, and Cleanup

## 目的

- 新構造へ切替を完了し、ドキュメントと実装の不一致を解消する
- 旧仕様を main から完全削除し、運用窓口を新構造へ一本化する

## 背景

- 改革途中は旧新フローが併存し、運用混乱を招きやすい

## スコープ

- cutover チェック
- ドキュメント更新
- 旧資産の即時削除

## 非ゴール

- 追加の大規模機能導入

## 具体タスク

1. cutover rehearsal plan を作成し、single cutover candidate commit を checkout した disposable rehearsal 環境で end-to-end rehearsal を成功させる
2. cutover チェックリストを作成し運用実施する
3. legacy 削除差分・docs 更新・bootstrap 入口更新を含む single cutover candidate commit の確定と反映順序を固定する
4. main 反映前後の ArgoCD 自動同期制御（一時停止 / controlled sync / 再開）を cutover 手順へ組み込む
5. `README.md` と `docs/README.md` を新責務に合わせ更新する
6. `docs/setup-guide.md` と `docs/applications.md` を新フローへ更新する
7. `docs/gitops-design.md` / `docs/operations-guide.md` / `docs/troubleshooting.md` を最終整合する
8. `docs/manifest-layout.md` / `docs/kubernetes-architecture.md` / `manifests/README.md` を最終整合する
9. `docs/external-access-guide.md` を `access/` 正本前提へ更新する
10. `AGENTS.md` を新責務に合わせ更新する
11. onboarding と validate の docs を Nix ベースの正式導線へ統一し、旧 ad-hoc tool install 手順を削除する
12. 旧 workflow / script / manifest の削除一覧を作成する
13. `monitoring` Application、`manifests/monitoring/`、Grafana Cloud 用 ExternalSecret、`deploy-grafana-*`、Grafana 監査 workflow を削除対象として single cutover candidate commit に含める
14. `apps/` 配下に残る access legacy（例: `apps/argocd`, `apps/rustfs`, `apps/cloudflared`, app 配下 route 定義）を削除対象として single cutover candidate commit に含める
15. Harbor access/runtime legacy（`harbor-patch`, 旧 `harbor-routes.yaml`, 旧 `harbor-image-cleanup-cronjob.yaml`, stale `prune:false` / `ignoreDifferences`）を削除対象として single cutover candidate commit に含める
16. `harbor-auth` / `github-auth` / `harbor-registry-secret` / `github-repo-secret` など legacy / duplicate credential Secret を single cutover candidate commit の削除対象として含める
17. `automation/templates/external-secrets/*.yaml` と `automation/templates/platform/argocd-github-oauth-secret.yaml` の stale secret template を削除対象として含める
18. `ghcr-nginx-charts-secret`、`harbor-registry` の `default` / `argocd` copy など repo だけでは未使用断定できない Secret は live cluster / ArgoCD inventory を確認し、不要なら cutover で削除し、必要なら owner と除去条件を記録する
19. `automation/scripts/verify.sh` と `automation/scripts/generate-cluster-diagram.sh` から `monitoring` namespace 必須前提を除去する
20. Harbor / RustFS を `rebuildable-stateful` として扱う場合の delete scope（Namespace / PVC / NFS archive / Secret）を確定し、clean rebuild 実施条件を checklist 化する
21. cutover 時点で旧資産を削除し、deprecate 期間を置かない
22. 代替監視基盤の導入は backlog 化し、改革完了条件から分離する
23. 残課題を backlog 化し、改革完了を宣言する
24. 検証対象 path（`manifests/`, `automation/`, `docs/`, `.github/`, `AGENTS.md`, `README.md`, `Makefile`）に grep ベースで旧記述が残っていないことを確認する
25. `automation/scripts/ci/validate.sh`（内部で `policy-check.sh` を含む）を cutover 判定の唯一の公開入口にする
26. monitoring legacy 削除後の最低 cutover 観測面は `tasks/cutover-checklist.md` を正本として固定する

## 変更対象

- `README.md`
- `AGENTS.md`
- `docs/README.md`
- `docs/quickstart.md`
- `docs/setup-guide.md`
- `docs/applications.md`
- `docs/external-access-guide.md`
- `docs/gitops-design.md`
- `docs/operations-guide.md`
- `docs/troubleshooting.md`
- `docs/manifest-layout.md`
- `docs/kubernetes-architecture.md`
- `manifests/README.md`
- `manifests/apps/`
- `manifests/access/`
- `tasks/cutover-checklist.md`
- `tasks/backlog.md`
- `manifests/monitoring/`
- `manifests/platform/argocd-config/`
- `manifests/platform/secrets/external-secrets/`
- `automation/platform/`
- `automation/scripts/verify.sh`
- `automation/scripts/generate-cluster-diagram.sh`
- `.github/workflows/weekly-version-audit.yml`
- 旧 workflow / script / manifest

## 検証

1. `tasks/cutover-checklist.md` の必須項目が 100% 完了していること
2. rehearsal 成功記録と rollback rehearsal 記録が残っていること
3. 旧手順への依存が残っていないこと
4. `automation/scripts/ci/validate.sh`（内部で `policy-check.sh` を含む）が成功すること
5. 以下が grep 0 件であること（対象: `manifests/`, `automation/`, `docs/`, `.github/`, `AGENTS.md`, `README.md`, `Makefile`）
   - `user-applications|user-application-definitions`
   - `add-runner\.sh|add-runners-bulk\.sh|add-runners-all|arc_repositories`
   - `grafana-cloud-monitoring|grafana-cloud-credentials|promtail-grafana-cloud-config|grafana-k8s-monitoring|chart:\s*k8s-monitoring|grafana\.github\.io/helm-charts|grafana\.net|deploy-grafana-monitoring|deploy-grafana-with-secret|deploy-grafana-monitoring-simple`
   - `harbor-auth|github-auth|harbor-registry-secret|github-repo-secret`
6. `manifests/apps/` 配下に `HTTPRoute|Gateway|Ingress|ClientSettingsPolicy|BackendTLSPolicy|ReferenceGrant` が残っていないこと
7. `.github/workflows/` と `automation/scripts/github-actions/` 配下で `kubectl rollout restart` が 0 件であること
8. `component-ownership-matrix.md` で定義した主要 runtime/access pair の target child Application が `Synced/Healthy` であること
9. 主要 access surface（例: `harbor.qroksera.com`, `rustfs.qroksera.com`, `argocd.qroksera.com`）が切替後に到達可能であること
10. Harbor cleanup CronJob が runtime owner 配下で in-cluster Harbor Service を到達先として設定され、`harbor-patch` 由来の legacy Application / 旧配置 / stale `ignoreDifferences` が除去されていること
11. `automation/scripts/verify.sh` と `automation/scripts/generate-cluster-diagram.sh` に `monitoring` namespace 必須前提が残っていないこと
12. `README.md` / `docs/README.md` / `docs/quickstart.md` / `docs/setup-guide.md` に `nix develop .#bootstrap` / `nix develop .#default` の正規手順が反映され、旧 validate ツール導入手順が残っていないこと
13. monitoring legacy を使わずに、`tasks/cutover-checklist.md` に定義した最低 cutover 観測面で成否を説明できること
14. `automation/templates/external-secrets/` と `automation/templates/platform/argocd-github-oauth-secret.yaml` に stale secret template が残っていないこと
15. live-confirm 対象 Secret の削除可否と根拠が cutover 記録または inventory に残っていること

## 完了条件

1. docs と実装が一致している
2. 旧フローが削除済み
3. cutover チェック項目が全件完了
4. `automation/scripts/ci/validate.sh`（内部で `policy-check.sh` を含む）が green である
5. 残課題が `backlog` として明確化されている
6. main ブランチに旧仕様が残っていない
7. `legacy-removal-inventory.md` に紐づく legacy 関連例外が Open 0 件
8. Harbor / RustFS の clean rebuild 判定と delete scope が実施記録に残っている
9. rehearsal 成功記録と rollback rehearsal 記録が残っている
10. Harbor cleanup CronJob が runtime owner 配下へ移り、in-cluster Harbor Service を使い、`harbor-patch` legacy が除去済み
11. Grafana Cloud と現行 monitoring stack の legacy が実装・docs・workflow・script から除去済み
12. Nix ベースの onboarding / validate 導線が docs に反映され、旧 ad-hoc 導線が除去済み
13. `apps/` workload と `access/` 公開/接続系の責務分離が docs / manifest / validate に反映済み
14. cutover 判定に必要な最低観測面が `tasks/cutover-checklist.md` を正本として monitoring legacy 非依存に定義・記録済み
15. legacy / duplicate credential Secret と stale secret template の削除結果が repo と live cluster の両方で説明可能である
16. live-confirm 対象 Secret の keep / delete 判断と根拠が記録済みである
