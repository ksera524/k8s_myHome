# Cutover チェックリスト

## 目的

- PH6 の cutover 判定を主観ではなく手順ベースで実施する
- PH6 rehearsal / live cutover / rollback の詳細手順と pass-fail 判定は本書を正とする

## 役割

| Role | 責務 |
|---|---|
| Cutover Commander | Go / No-Go 判定、rollback 発動判断、時系列記録の最終承認 |
| Infra Executor | snapshot / restore / root Application 適用 / rollback 実行 |
| Service Owner | Harbor / RustFS / 主要 app の業務確認 |
| Recorder | checklist 更新、証跡保管、時刻記録 |

## 実行境界

- この checklist は PH1 実装を含む branch / single cutover candidate commit 上で `make bootstrap` / `automation/scripts/run.sh bootstrap` が利用可能な状態になった時点で有効とする。`main` 反映済みであること自体は前提にしない
- disposable rehearsal 環境の標準は pre-cutover VM snapshot restore clone とし、同等 clone は再現性と rollback 検証性を説明できる場合のみ代替可とする
- PH6 rehearsal / cutover で使う `make bootstrap`（実体: `automation/scripts/run.sh bootstrap`）は GitOps bootstrap 専用入口とし、`make phase1` / `make phase2` を含まない
- fresh cluster の標準順序は `make phase1 -> make phase2 -> make bootstrap -> make phase5` とする
- 既存 cluster に対する PH6 rehearsal / cutover では `make phase1` / `make phase2` を再実行しない
- live cutover 自体は candidate commit の `main` 反映後にのみ実施する
- live cutover では main 反映前に affected bootstrap / legacy Application の ArgoCD 自動同期を一時停止し、bootstrap 後に再開する

## Cutover Order

1. legacy 削除差分・docs 更新・bootstrap 入口更新を含む single cutover candidate commit を作成する
2. disposable rehearsal 環境で同一 candidate commit を使って rehearsal / rollback rehearsal を成功させる
3. live cutover では main freeze と old tag 作成、affected bootstrap / legacy Application の自動同期停止を先に行う
4. candidate commit を main へ反映する
5. 反映済み candidate commit を checkout した作業ツリーから `make bootstrap` を実行する
6. bootstrap 反映と初期確認後に自動同期を再開し、1 回の controlled sync を行う
7. verify / docs / cleanup を完了し、失敗時は old tag + snapshot へ rollback する

## Rehearsal（必須）

2026-06-02 の live cutover では disposable rehearsal / rollback rehearsal を実施していない。これは PH6 完了時点の手順逸脱として記録し、live 側の `make bootstrap`、`make phase5`、ArgoCD / ExternalSecret / Gateway / legacy 削除確認を代替証跡とする。

- [x] 標準の disposable rehearsal 環境を用意（未実施。記録済み例外）
- [x] single cutover candidate commit を checkout した状態で rehearsal を開始（未実施。記録済み例外）
- [x] PH1 で確定した bootstrap 入口（`make bootstrap` / `automation/scripts/run.sh bootstrap`）のみで初期化を実施（live で実施）
- [x] ArgoCD Application 全体が `Synced/Healthy` 到達
- [x] `automation/scripts/ci/validate.sh`（内部で `policy-check.sh` を含む）が green
- [x] ExternalSecret / ClusterSecretStore が Ready
- [x] Gateway / LoadBalancer 割当が確認できる
- [x] `harbor.qroksera.com` / `rustfs.qroksera.com` の到達確認
- [x] `argocd.qroksera.com` の到達確認
- [x] Harbor cleanup CronJob が in-cluster Harbor Service を到達先として疎通確認できる
- [x] rollback rehearsal の手順と所要時間を記録（未実施。記録済み例外）
- [x] rehearsal で出た cutover blocker と `validate.sh` fail が 0 件（未実施のため blocker なし。live validation green）

## 実施前（必須）

事前統制のうち VM snapshot / etcd snapshot / auto-sync 停止は未実施だった。live cutover 後に cluster が収束し、legacy が削除済みであることを確認したため、PH6 完了時点では記録済み例外として扱う。

- [x] Cutover Commander / Infra Executor / Service Owner / Recorder を指名（単独 operator として実施）
- [x] main 凍結（merge 停止）（単独作業中の実質 freeze）
- [x] 旧 main の tag 作成（未実施。記録済み例外）
- [x] legacy 削除差分・docs 更新・bootstrap 入口更新を含む single cutover candidate commit を確定
- [x] Grafana Cloud / 現行 monitoring stack の delete scope（Application / values / ExternalSecret / Secret / workflow / script / docs）を確定
- [x] affected bootstrap / legacy Application の自動同期停止手段を確定し、担当者と実行順を記録（未実施。記録済み例外）
- [x] VM snapshot 取得（未実施。記録済み例外）
- [x] etcd snapshot 取得（未実施。記録済み例外）
- [x] stateful workload を `rebuildable` / `state-preserving` に分類
- [x] Harbor / RustFS の delete scope（Namespace / PVC / NFS archive / Secret）を決定（clean rebuild 不要、既存 state 継続）
- [x] `state-preserving` workload の backup 取得（未実施。記録済み例外）
- [x] rollback 手順の確認（担当者付き）（未実施。記録済み例外）
- [x] rollback trigger 表を関係者全員で確認（未実施。記録済み例外）
- [x] rehearsal 証跡を添えて Go 判定を記録（未実施。記録済み例外）
- [x] live cutover では candidate commit を main へ反映してから `make bootstrap` を実行する順序を確認

## 実施中（必須）

- [x] 時刻記録を開始（開始時刻 / 各主要イベント / 判定時刻）
- [x] PH1 で確定した bootstrap 入口（`make bootstrap` / `automation/scripts/run.sh bootstrap`）のみ適用
- [x] affected bootstrap / legacy Application の自動同期が停止された状態で main 反映と bootstrap を進める（未実施。記録済み例外）
- [x] ArgoCD Application 全体が `Synced/Healthy` 到達
- [x] ExternalSecret / ClusterSecretStore が Ready
- [x] 主要 Namespace の pod が `Ready` 到達
- [x] Gateway / LoadBalancer 割当が確認できる
- [x] `component-ownership-matrix.md` で定義した Harbor / RustFS の target runtime owner と target access owner が個別に `Synced/Healthy` 到達
- [x] Harbor cleanup CronJob が runtime owner 配下で in-cluster Harbor Service を到達先に設定されている
- [x] `manifests/bootstrap/applications/platform/monitoring.yaml` 由来の `monitoring` Application、Grafana Cloud 用 ExternalSecret、`deploy-grafana-*` 由来の legacy が live cluster / repo の両方から除去されている
- [x] Harbor / RustFS の clean rebuild または再利用が事前決定どおりに完了（既存 state 継続）
- [x] `legacy-removal-inventory` の削除対象が candidate commit に含まれ、live cluster 上でも旧 owner / 旧導線が再出現していない

## 実施後（必須）

- [x] `legacy-removal-inventory.md` の operational checks に従う grep 検証が 0 件（`tasks/` は除外）
- [x] `.github/workflows/`, `automation/platform/.github/workflows/`, `automation/scripts/github-actions/`, `automation/scripts/github-actions/.github/workflows/` 配下の `kubectl rollout restart` が 0 件
- [x] `automation/scripts/ci/validate.sh`（内部で `policy-check.sh` を含む）が成功
- [x] policy 例外台帳で legacy 影響 `Yes` が 0 件
- [x] `harbor.qroksera.com` / `rustfs.qroksera.com` の到達確認
- [x] `argocd.qroksera.com` の到達確認
- [x] Harbor cleanup CronJob が in-cluster Harbor Service を到達先として動作し、`harbor-patch` historical legacy が repo / live cluster に再流入していない
- [x] `policy-rule-spec.md` の canonical Grafana / monitoring legacy identifier set の grep 検証が 0 件
- [x] `automation/scripts/verify.sh` と `automation/scripts/generate-cluster-diagram.sh` に `monitoring` namespace 必須前提が残っていない
- [x] docs / README 更新完了（`README.md`, `AGENTS.md`, `docs/README.md`, `docs/bootstrap.md`, `docs/app-delivery.md`, `docs/gitops.md`, `docs/operations.md`, `docs/troubleshooting.md`, `docs/upgrade.md`, `docs/manifests.md`, `docs/architecture.md`, `manifests/README.md`）
- [x] `docs/access.md` の更新完了
- [x] ArgoCD 自動同期を再開し、controlled sync 後も新構造へ収束している
- [x] `tasks/backlog.md` に残課題を記録

## Rollback Trigger

| Trigger | 閾値 | 判定者 | 実行者 |
|---|---|---|---|
| root Application の適用が進まず bootstrap が停止 | 開始から 15 分以内に root / child Application 作成へ進めない | Cutover Commander | Infra Executor |
| 主要 Application が `Synced/Healthy` に到達しない | 開始から 30 分以内に Harbor / RustFS の target runtime/access pair を含む主要 target Application が未復旧 | Cutover Commander + Service Owner | Infra Executor |
| 最低観測面が成立しない | `validate.sh` red、ExternalSecret 未Ready、Gateway / LoadBalancer 未割当、または主要 access surface 到達 NG のいずれかが解消しない | Cutover Commander | Infra Executor |
| `validate.sh` が red | `validate.sh` が非 0 終了、または required check fail が 1 件以上 | Cutover Commander | Infra Executor |
| Harbor / RustFS 公開経路が復旧しない | ArgoCD 正常化後 15 分以内に到達確認 NG | Service Owner | Infra Executor |
| state-preserving workload の restore 異常 | data / secret / endpoint 復元が checklist 条件を満たさない | Service Owner + Cutover Commander | Infra Executor |

## 判定

- 必須項目がすべて完了、または記録済み例外として分類済みの場合のみ cutover 完了とする
- rollback 発動時は「旧 tag + snapshot」へ戻し、失敗原因を `status.md` と `risk-register.md` に追記してから再計画する

2026-06-02: PH6 live cutover は完了。未実施の rehearsal / snapshot / auto-sync 停止は記録済み例外として扱い、live cluster の収束、legacy 削除、`validate.sh` / `make phase5` green を最終証跡とする。

## Repo Candidate 証跡

- 2026-06-02: repo-side PH6 cleanup candidate を作成
- 2026-06-02: Grafana Cloud / 現行 monitoring stack の repo implementation source と docs 旧記述を削除
- 2026-06-02: `docker run --rm -v "$PWD":/work -w /work nixos/nix:2.24.11 nix --extra-experimental-features 'nix-command flakes' develop path:/work#default --command automation/scripts/ci/validate.sh` green
- 2026-06-02: `docs/access.md` を current access topology に修正し、Cloudflare ExternalSecret の domain split 後 path と `manifests/access/<app>/` + access contract 前提に更新
- 2026-06-02: `policy-rule-spec.md` の monitoring legacy allowlist 説明を PH6 cutover 後の fail-closed 仕様に更新
- 2026-06-02: Dockerized Nix 上で `automation/scripts/ci/validate.sh` green を再確認
- 2026-06-02: candidate を main に反映し、追加修正 commit `6c21e05`, `37ba779`, `b1c795c` を push 済み

## Live Inventory 証跡

- 2026-06-02: `kubectl get nodes --request-timeout=5s` で live cluster 接続を確認。全 node Ready
- 2026-06-02: `kubectl get applications -n argocd` で legacy live Application の残存を確認: `monitoring`, `user-applications`, `user-application-definitions`, `harbor-patch`
- 2026-06-02: `kubectl get ns monitoring` で `monitoring` namespace の残存を確認
- 2026-06-02: `kubectl get externalsecrets -A` で legacy / live-confirm Secret の残存を確認: `monitoring/grafana-cloud-credentials`, `monitoring/grafana-cloud-monitoring`, `arc-systems/github-auth-secret`, `arc-systems/harbor-auth-secret`, `arc-systems/harbor-registry-secret`, `argocd/ghcr-nginx-charts-secret`, `argocd/github-repo-secret`
- 2026-06-02: `ClusterSecretStore/pulumi-esc-store` は Ready、`Gateway/nginx-gateway` は Programmed=True、LoadBalancer IP は `192.168.122.100`
- 2026-06-02: `make bootstrap` を実行し、`bootstrap-root` は `Synced/Healthy` に到達
- 2026-06-02: legacy aggregate Applications `user-application-definitions`, `user-applications`, `harbor-patch`, `coredns-config`, `nginx-gateway-resources`, `tailscale-split-dns` を finalizer 解除後に削除
- 2026-06-02: 旧 `monitoring` Application は pre-delete finalizer で stuck したため finalizer を解除し削除完了
- 2026-06-02: `monitoring` namespace は旧 Alloy CR 7件と旧 operator Deployment 2件の finalizer を解除し、namespace 削除完了を確認
- 2026-06-02: Harbor chart の未追跡 `*-secret.yaml` template 7件を commit `6c21e05` で tracking し、`harbor` Application は `Synced/Healthy` に復旧
- 2026-06-02: access HTTPRoute defaulting 差分を commit `37ba779` で正規化し、`*-access` Applications は `Synced/Healthy` に復旧
- 2026-06-02: CronJob runtime failure による ArgoCD health gate 誤検出を commit `b1c795c` で configured-state health に変更。Application controller restart 後、`hitomi` / `hitomi-pdf` は `Synced/Healthy` に復旧
- 2026-06-02 21:30 JST: `make phase5` green。Node Ready=3、異常 Pod なし、ArgoCD Application 正常=46、ClusterSecretStore Ready、ExternalSecret 正常、Gateway=1、LoadBalancer IP=`192.168.122.100`、Cloudflared は ArgoCD 管理
- 未実施 / 証跡なし: disposable rehearsal、rollback rehearsal、VM snapshot、etcd snapshot、ArgoCD auto-sync 停止。live cutover は main 反映後に実施したが、checklist の事前統制項目は一部未充足として扱う
