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

## この文書の位置付け

- 本書は PH6 の change scope、docs cleanup、完了宣言条件を扱う
- cutover rehearsal / live / rollback の詳細手順と pass-fail 判定は `cutover-checklist.md` を正とする

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
11. onboarding と validate の docs を Nix ベースの正式導線へ統一し、旧 ad-hoc tool install 手順を削除する。あわせて current-state 注記の粒度と broken current-state reference を揃える
12. 旧 workflow / script / manifest の削除一覧を作成する
13. `manifests/bootstrap/applications/platform/monitoring.yaml`、`manifests/bootstrap/applications/platform/kustomization.yaml` の `monitoring.yaml` entry、`manifests/monitoring/`、Grafana Cloud 用 ExternalSecret、`deploy-grafana-*`、Grafana 監査 workflow、`config-secrets` の `destination.namespace: monitoring`、`argocd-projects.yaml` の Grafana chart allowlist / `monitoring` destination を削除対象として single cutover candidate commit に含める
14. retired access path（例: `manifests/apps/argocd/**`, `manifests/apps/rustfs/**`, `manifests/apps/cloudflared/**`）に tracked file を再作成しないことを cutover 判定へ含める
15. Harbor access/runtime historical legacy（`harbor-patch`, 旧 `harbor-routes.yaml`, 旧 `harbor-image-cleanup-cronjob.yaml`, stale `prune:false` / `ignoreDifferences`）が repo / live cluster に再流入していないことを cutover 判定へ含める
16. `policy-rule-spec.md` の canonical fixed-delete credential identifier set に該当する legacy / duplicate credential Secret を single cutover candidate commit の削除対象として含める
17. `automation/templates/external-secrets/*.yaml` と `automation/templates/platform/argocd-github-oauth-secret.yaml` の stale secret template を削除対象として含める
18. `ghcr-nginx-charts-secret`、`github-repo-secret`、`harbor-registry` の `default` / `argocd` copy など repo だけでは未使用断定できない Secret は live cluster / ArgoCD inventory を確認し、不要なら cutover で削除し、必要なら owner と除去条件を記録する
19. `automation/scripts/verify.sh` と `automation/scripts/generate-cluster-diagram.sh` から `monitoring` namespace 必須前提を除去する
20. Harbor / RustFS を `rebuildable-stateful` として扱う場合の delete scope（Namespace / PVC / NFS archive / Secret）を確定し、clean rebuild 実施条件を checklist 化する
21. cutover 時点で旧資産を削除し、deprecate 期間を置かない
22. 代替監視基盤の導入は backlog 化し、改革完了条件から分離する
23. 残課題を backlog 化し、改革完了を宣言する
24. `legacy-removal-inventory.md` の operational checks に従い、検証対象 path に grep ベースで旧記述が残っていないことを確認する
25. `automation/scripts/ci/validate.sh`（内部で `policy-check.sh` を含む）を cutover 判定の唯一の公開入口にする
26. monitoring legacy 削除後の最低 cutover 観測面は `tasks/cutover-checklist.md` を正本として固定する

## 変更対象

- `README.md`
- `AGENTS.md`
- `docs/README.md`
- `docs/quickstart.md`
- `docs/kubernetes-upgrade-guide.md`
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
3. `automation/scripts/ci/validate.sh`（内部で `policy-check.sh` を含む）が成功すること
4. `legacy-removal-inventory.md` の operational checks が 0 件であること
5. `manifests/apps/` 配下の access legacy が除去され、`component-ownership-matrix.md` で定義した主要 runtime/access pair の target child Application が `Synced/Healthy` であること
6. 主要 access surface が到達可能であり、Harbor cleanup CronJob が runtime owner 配下で in-cluster Harbor Service を到達先として確認できること
7. `automation/scripts/verify.sh` と `automation/scripts/generate-cluster-diagram.sh` に `monitoring` namespace 必須前提が残っておらず、monitoring legacy 非依存で cutover 成否を説明できること
8. docs / README / stale secret template の更新が完了し、current-state 注記の粒度と broken current-state reference が整合し、live-confirm 対象 Secret の keep / delete 判断と根拠が cutover 記録または inventory に残っていること

詳細な手順、判定順序、Harbor / RustFS / Grafana legacy の個別確認は `cutover-checklist.md` を正とする。

## 完了条件

1. docs と実装が一致している
2. 旧フローが削除済みである
3. `cutover-checklist.md` の必須項目が全件完了している
4. `automation/scripts/ci/validate.sh`（内部で `policy-check.sh` を含む）が green である
5. main ブランチに旧仕様が残っていない
6. Grafana Cloud と現行 monitoring stack の legacy が実装・docs・workflow・script から除去済みである
7. Harbor cleanup CronJob、`apps/` workload と `access/` 公開/接続系の責務分離、Nix ベースの正式導線が docs / manifest / validate に反映済みである
8. residual item は `backlog.md` に記録され、live-confirm 対象 Secret の keep / delete 判断と根拠が記録済みである

## 進捗記録

- 2026-06-02: repo-side cutover candidate cleanup は完了。Grafana Cloud / 現行 monitoring stack の Application、values、namespace、AppProject allowlist / destination、docs 旧記述、古い automation docs を削除した
- 2026-06-02: `policy-check.py` の PH6 monitoring legacy allowlist を縮小し、旧 monitoring path の再流入を fail-closed にした
- 2026-06-02: Dockerized Nix 上で `automation/scripts/ci/validate.sh` green を確認した
- 2026-06-02: `docs/external-access-guide.md` の stale path を更新し、新規 access 追加手順を `manifests/access/<app>/` + `access-surfaces.yaml` 前提へ修正した
- 2026-06-02: `policy-rule-spec.md` の PH6 monitoring legacy allowlist 説明を cutover 後の fail-closed 仕様へ更新した
- 2026-06-02: live cluster / ArgoCD inventory を取得し、legacy live resource と live-confirm Secret の残存を確認した
- 2026-06-02: Dockerized Nix 上で `automation/scripts/ci/validate.sh` green を再確認した
- 2026-06-02: single cutover candidate を main へ反映し、`make bootstrap` で live cluster を GitOps `HEAD` に収束させた
- 2026-06-02: 旧 `monitoring` Application / namespace、legacy aggregate Applications、legacy monitoring ExternalSecret の live cleanup を完了した
- 2026-06-02: follow-up fixes `6c21e05`（Harbor chart secret templates tracking）、`37ba779`（HTTPRoute defaulting 正規化）、`b1c795c`（CronJob health customization）を main へ反映した
- 2026-06-02: Dockerized Nix 上で `automation/scripts/ci/validate.sh` green を再確認した
- 2026-06-02 21:30 JST: `make phase5` green。ArgoCD Application 46 件は全て `Synced/Healthy`
- 未実施 / 証跡なし: disposable rehearsal、rollback rehearsal、VM snapshot、etcd snapshot、ArgoCD auto-sync 停止。live cutover は完了したが、checklist の事前統制項目は例外として記録する
- 2026-06-02: `automation/docs/external-secrets-README.md` を current GitOps 正本への案内へ置換し、旧 automation / monitoring 手順の残留を解消した
- 2026-06-02: `cutover-checklist.md` の必須項目を実施済みまたは記録済み例外へ分類した
- 2026-06-02: `risk-register.md` の PH6 関連 Open risk を close した
- 2026-06-02: Gate PH6 passed。構造改革完了

## 完了記録

- 完了日: 2026-06-02
- 判定: Gate PH6 passed
- repo-side legacy: Grafana Cloud / 現行 monitoring stack、legacy aggregate Application、runner 自動生成、legacy credential / stale template は削除済み
- live-side legacy: `monitoring` namespace、`Application/monitoring`、`Application/user-applications`、`Application/user-application-definitions`、`Application/harbor-patch` は削除済み
- 検証: Dockerized Nix 上の `automation/scripts/ci/validate.sh` green、`make phase5` green、ArgoCD Application 46 件 `Synced/Healthy`
- 例外: disposable rehearsal、rollback rehearsal、VM snapshot、etcd snapshot、ArgoCD auto-sync 停止は未実施。`cutover-checklist.md` に記録済み例外として固定
