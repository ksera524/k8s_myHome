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

- [ ] 標準の disposable rehearsal 環境を用意（pre-cutover VM snapshot restore clone。代替時は同等性の説明を記録）
- [ ] single cutover candidate commit を checkout した状態で rehearsal を開始
- [ ] PH1 で確定した bootstrap 入口（`make bootstrap` / `automation/scripts/run.sh bootstrap`）のみで初期化を実施
- [ ] ArgoCD Application 全体が `Synced/Healthy` 到達
- [ ] `automation/scripts/ci/validate.sh`（内部で `policy-check.sh` を含む）が green
- [ ] ExternalSecret / ClusterSecretStore が Ready
- [ ] Gateway / LoadBalancer 割当が確認できる
- [ ] `harbor.qroksera.com` / `rustfs.qroksera.com` の到達確認
- [ ] `argocd.qroksera.com` の到達確認
- [ ] Harbor cleanup CronJob が in-cluster Harbor Service を到達先として疎通確認できる
- [ ] rollback rehearsal の手順と所要時間を記録
- [ ] rehearsal で出た cutover blocker と `validate.sh` fail が 0 件

## 実施前（必須）

- [ ] Cutover Commander / Infra Executor / Service Owner / Recorder を指名
- [ ] main 凍結（merge 停止）
- [ ] 旧 main の tag 作成
- [ ] legacy 削除差分・docs 更新・bootstrap 入口更新を含む single cutover candidate commit を確定
- [ ] Grafana Cloud / 現行 monitoring stack の delete scope（Application / values / ExternalSecret / Secret / workflow / script / docs）を確定
- [ ] affected bootstrap / legacy Application の自動同期停止手段を確定し、担当者と実行順を記録
- [ ] VM snapshot 取得
- [ ] etcd snapshot 取得
- [ ] stateful workload を `rebuildable` / `state-preserving` に分類
- [ ] Harbor / RustFS の delete scope（Namespace / PVC / NFS archive / Secret）を決定
- [ ] `state-preserving` workload の backup 取得
- [ ] rollback 手順の確認（担当者付き）
- [ ] rollback trigger 表を関係者全員で確認
- [ ] rehearsal 証跡を添えて Go 判定を記録
- [ ] live cutover では candidate commit を main へ反映してから `make bootstrap` を実行する順序を確認

## 実施中（必須）

- [ ] 時刻記録を開始（開始時刻 / 各主要イベント / 判定時刻）
- [ ] PH1 で確定した bootstrap 入口（`make bootstrap` / `automation/scripts/run.sh bootstrap`）のみ適用
- [ ] affected bootstrap / legacy Application の自動同期が停止された状態で main 反映と bootstrap を進める
- [ ] ArgoCD Application 全体が `Synced/Healthy` 到達
- [ ] ExternalSecret / ClusterSecretStore が Ready
- [ ] 主要 Namespace の pod が `Ready` 到達
- [ ] Gateway / LoadBalancer 割当が確認できる
- [ ] `component-ownership-matrix.md` で定義した Harbor / RustFS の target runtime owner と target access owner が個別に `Synced/Healthy` 到達
- [ ] Harbor cleanup CronJob が runtime owner 配下で in-cluster Harbor Service を到達先に設定されている
- [ ] `manifests/bootstrap/applications/platform/monitoring.yaml` 由来の `monitoring` Application、Grafana Cloud 用 ExternalSecret、`deploy-grafana-*` 由来の legacy が live cluster / repo の両方から除去されている
- [ ] Harbor / RustFS の clean rebuild または再利用が事前決定どおりに完了
- [ ] `legacy-removal-inventory` の削除対象が candidate commit に含まれ、live cluster 上でも旧 owner / 旧導線が再出現していない

## 実施後（必須）

- [ ] `legacy-removal-inventory.md` の operational checks に従う grep 検証が 0 件（`tasks/` は除外）
- [ ] `.github/workflows/`, `automation/platform/.github/workflows/`, `automation/scripts/github-actions/`, `automation/scripts/github-actions/.github/workflows/` 配下の `kubectl rollout restart` が 0 件
- [ ] `automation/scripts/ci/validate.sh`（内部で `policy-check.sh` を含む）が成功
- [ ] policy 例外台帳で legacy 影響 `Yes` が 0 件
- [ ] `harbor.qroksera.com` / `rustfs.qroksera.com` の到達確認
- [ ] `argocd.qroksera.com` の到達確認
- [ ] Harbor cleanup CronJob が in-cluster Harbor Service を到達先として動作し、`harbor-patch` historical legacy が repo / live cluster に再流入していない
- [ ] `policy-rule-spec.md` の canonical Grafana / monitoring legacy identifier set の grep 検証が 0 件
- [ ] `automation/scripts/verify.sh` と `automation/scripts/generate-cluster-diagram.sh` に `monitoring` namespace 必須前提が残っていない
- [ ] docs / README 更新完了（`README.md`, `AGENTS.md`, `docs/README.md`, `docs/quickstart.md`, `docs/setup-guide.md`, `docs/applications.md`, `docs/gitops-design.md`, `docs/operations-guide.md`, `docs/troubleshooting.md`, `docs/kubernetes-upgrade-guide.md`, `docs/manifest-layout.md`, `docs/kubernetes-architecture.md`, `manifests/README.md`）
- [ ] `docs/external-access-guide.md` の更新完了
- [ ] ArgoCD 自動同期を再開し、controlled sync 後も新構造へ収束している
- [ ] `tasks/backlog.md` に残課題を記録

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

- 必須項目がすべて完了した場合のみ cutover 完了とする
- rollback 発動時は「旧 tag + snapshot」へ戻し、失敗原因を `status.md` と `risk-register.md` に追記してから再計画する
