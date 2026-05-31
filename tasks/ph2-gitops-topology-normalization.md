# PH2: GitOps Topology Normalization and Access Extraction

## 目的

- App-of-Apps 配下の所有関係を正規化し、重複管理と誤解をなくす
- owner を一意化し、差分レビュー可能な粒度へ再構成する
- `apps` 配下から公開/接続系 resource を追い出し、`access` ドメインへ抽出する

## 背景

- 単一巨大ファイルと二重経路により、どの Application が owner か追いにくい
- workload 本体と公開/接続系が同じパスに混在し、責務境界が曖昧

## スコープ

- Application 定義の分割
- owner 一意化
- `apps` から `access` への公開/接続系 resource の抽出
- `user-applications` / `user-application-definitions` を新正本から切り離し、PH6 cutover で完全廃止する準備
- `monitoring` Application と Grafana Cloud 前提の owner/監査依存を PH6 cutover 用削除差分として準備
- 図と実装の一致
- empty dir / dead path の棚卸し

## 非ゴール

- app repo の CI 方式変更

## 設計固定

1. access owner は `service access` と `shared access plane` の 2 層で固定する
2. `service access` owner は `argocd-access`, `harbor-access`, `rustfs-access`, `blog-access`, `cooklog-access`, `api-hub-access`, `hitomi-upload-viewer-access` とする
3. `shared access plane` owner は `gateway-shared`, `cloudflared`, `dns-core`, `dns-tailscale` とする
4. `Gateway` resource / listener 基盤は controller / CRD と分離し、`gateway-shared` が `manifests/access/gateway/` を所有する
5. `Cloudflared`, `CoreDNS`, `Tailscale Split DNS` は service ごとに複製せず、shared access plane owner に集約する
6. child `Application` の粒度は `1 owner / 1 file / 1 path` に固定する
7. remote chart を含む runtime owner でも child `Application` の例外を作らず、repo-local wrapper path を正本にする
8. empty dir / dead path は reservation せず削除する
9. ArgoCD `AppProject` は `core`, `infrastructure`, `platform`, `access`, `apps` の 5 系統を canonical とし、`access` child Application は専用 project に固定する

## 抽出順序

1. shared foundation を先に定義する
   - `gateway-shared` の child `Application` / path / sync wave を確定
   - `cloudflared`, `dns-core`, `dns-tailscale` の child `Application` / path / sync wave を確定
2. service access route を分離する
   - `blog`, `cooklog`, `api-hub`, `hitomi-upload-viewer` の `HTTPRoute` を service access owner へ移す
3. legacy external app を service access owner へ置換する
   - `argocd-external`, `rustfs-external` を canonical service access owner に置き換える
4. Harbor を split owner へ再分類する
   - `harbor-routes.yaml` の route / policy を `harbor-access` へ移し、cleanup CronJob は runtime owner に残して in-cluster Harbor Service を使う
   - `harbor-patch` Application と旧 `prune:false` / `ignoreDifferences` は同一 change set で除去する
5. shared publisher を移す
   - `CoreDNS`, `Tailscale Split DNS`, `Cloudflared` の publication 定義を shared access plane owner に移し、旧 path を同一 change set から除去する

## sync wave 原則

1. `infra controllers`
2. `gateway-shared`
3. `runtime owners`
4. `service access owners`
5. `shared publishers`

## 具体タスク

1. `manifests/bootstrap/app-of-apps.yaml` を root Application 1 件へ再定義
2. child Application を `manifests/bootstrap/applications/{core,infrastructure,platform,access,user-apps}/` に `1 Application / 1 file` で分割
3. `user-applications` / `user-application-definitions` を新正本から切り離し、PH6 cutover で削除する差分を準備
4. `manifests/bootstrap/applications/user-apps/` を runtime owner の正本として整理する
5. `manifests/bootstrap/applications/access/` を access owner の正本として整理する
6. `manifests/apps/**` にある `HTTPRoute` などの公開/接続系 resource を `manifests/access/**` へ移す target state を、`service access` と `shared access plane` の 2 層 owner で設計する
7. `argocd-external`, `rustfs-external`, `cloudflared`, `nginx-gateway-resources`, Harbor routes, app 配下の route 類を canonical access owner に再分類する
8. Harbor runtime owner を `manifests/platform/harbor/` の repo-local wrapper へ収束させ、cleanup CronJob を同 owner に移し、到達先を in-cluster Harbor Service に切り替える
9. `harbor-patch` と旧 `prune:false` / stale `ignoreDifferences` を legacy 削除差分へ移す
10. AppProject を `core` / `infrastructure` / `platform` / `access` / `apps` の 5 系統で再設計し、`sourceRepos` / `destinations` / `clusterResourceWhitelist` を最小権限に固定する。owner 一意性の最終担保は PH5 の resource collision check に委ねる
11. `automation/platform/platform-deploy.sh` と `automation/scripts/verify.sh` の旧 owner 参照を更新し、個別 Application / access child Application 確認へ移行する
12. `.github/workflows/weekly-version-audit.yml` の `app-of-apps.yaml` 依存を更新する
13. `manifests/bootstrap/app-of-apps.yaml` の `monitoring` Application を新正本から切り離し、PH6 cutover で削除する差分を準備する
14. `.github/workflows/weekly-version-audit.yml` の Grafana k8s-monitoring 監査ロジックを削除対象として整理する
15. `docs/diagrams/app-of-apps-sync-wave.md` から Monitoring wave を除去する前提で実装との差分を整理し、diagram / docs を同期する
16. PH2 判定用の暫定 app owner / access owner / dead path チェック手順を定義し実行する
17. rendered resource collision check の恒久実装を PH5 へ引き継ぐ

## 変更対象

- `manifests/bootstrap/`
- `manifests/bootstrap/applications/`
- `manifests/bootstrap/applications/user-apps/`
- `manifests/bootstrap/applications/access/`
- `manifests/access/`
- `manifests/infrastructure/networking/`
- `manifests/platform/argocd-config/`
- `automation/platform/platform-deploy.sh`
- `automation/scripts/verify.sh`
- `automation/scripts/ci/`
- `.github/workflows/weekly-version-audit.yml`
- `docs/diagrams/app-of-apps-sync-wave.md`
- `docs/setup-guide.md`
- `docs/gitops-design.md`
- `docs/external-access-guide.md`
- `docs/applications.md`

## 検証

1. 全 child Application の `metadata.name` と `spec.source.path` が一意であること
2. `apps/**` に公開/接続系 resource を残さない target topology が定義されていること
3. `service access` と `shared access plane` の owner 境界、および sync wave 原則が図と manifest で一致していること
4. Harbor の runtime owner が repo-local wrapper path に収束し、cleanup CronJob が runtime owner 側へ帰属していること
5. `user-applications` / `user-application-definitions` の runtime 依存が新 owner へ置き換わり、削除差分が PH6 cutover 用として準備済みであること
6. child Application 追加/変更が「1ファイル差分」でレビュー可能であること
7. `monitoring` Application と Grafana k8s-monitoring 監査依存の削除差分が PH6 cutover 用として準備済みであること
8. empty dir / dead path が reservation として残っていないこと

## 完了条件

1. legacy 集約 owner がなく、app child Application の owner 重複がない
2. `user-applications` / `user-application-definitions` の代替 owner が成立し、削除差分が PH6 cutover 入力として確定している
3. `apps/**` から access resource を排除する target topology が確定している
4. `access` child Application 群の責務と配置先が、`service access` と `shared access plane` の 2 層で定義済みである
5. Harbor の runtime/access/optional ops 境界が repo-local wrapper + `harbor-access` + opt-in overlay の形で定義済みである
6. App-of-Apps 構成が差分レビュー可能な粒度になっている
7. 依存順を docs で再現できる
8. bootstrap/verify/audit/docs の参照先が新トポロジへ切り替わっている
9. 暫定チェック手順が定義・実行済みで、恒久ルールが PH5 へ引き継がれている
10. `monitoring` Application の owner / docs / audit 依存が新 target state から切り離されている
11. empty dir / dead path が削除方針で整理され、予約ディレクトリが残っていない
12. `access` child Application 群が専用 `AppProject` に乗り、現行 `apps` / `platform` との権限境界が文書化されている
