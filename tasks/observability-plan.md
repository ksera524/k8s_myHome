# Observability Plan

## 目的

- PH6 で削除した旧監視 stack の代替を、新規 `observability` owner として設計する
- GitOps topology / runtime-access 分離 / contract ルールに沿って導入順序を固定する
- 実装前に監視対象、公開面、secret、検証条件を明確にする

## 方針

1. 旧 `monitoring` owner / Grafana Cloud 連携は復活させない
2. 新規 owner 名は `observability` とする
3. runtime は `manifests/platform/observability/` に置く
4. 公開が必要な場合は `manifests/access/observability/` に分離する
5. hostname を持つ場合は `manifests/contracts/home-lab/access-surfaces.yaml` に surface を追加する
6. secret が必要な場合は `manifests/platform/secrets/external-secrets/` の既存 domain へ配置し、必要なら `observability` domain 追加を別途判断する
7. bootstrap script から直接 deploy せず、ArgoCD child Application で管理する

## 推奨構成

初期導入は self-hosted の軽量構成を推奨する。

| 項目 | 推奨 | 理由 |
|---|---|---|
| metrics backend | VictoriaMetrics single-node | home-lab で運用が軽く、Prometheus remote-write 互換を使いやすい |
| dashboard | Grafana OSS | dashboard / datasource 管理が標準的で、SaaS token 不要 |
| alerting | Alertmanager 互換または Grafana alert | 初期は必須にせず、後続で段階導入 |
| external uptime | Uptime Kuma または Cloudflare health check | cluster 内 metrics と外形監視を分離できる |

初期実装は metrics backend + kube-state-metrics を先行し、Grafana dashboard / alerting / uptime は次段階に分ける。Grafana は admin credential の ExternalSecret 方針を固定してから導入する。

## 監視対象

### Phase O1: 最小観測面

- Kubernetes Node Ready
- Pod Ready / restart count
- ArgoCD Application sync / health
- ExternalSecret Ready
- Gateway Programmed / LoadBalancer IP
- Cloudflared tunnel Pod Ready
- Harbor core / registry / portal Pod Ready
- RustFS Pod Ready / PVC Bound

### Phase O2: 運用観測面

- app namespace の Deployment availability
- CronJob の直近 Job 成否
- cert-manager Certificate Ready
- NFS provisioner / StorageClass 関連の PVC provisioning
- RunnerScaleSet / ARC controller health

### Phase O3: 外形監視

- `argocd.qroksera.com`
- `harbor.qroksera.com`
- `rustfs.qroksera.com`
- public app surfaces
- internal surfaces は Tailnet / CoreDNS 経由の別 check として扱う

## GitOps 配置案

### runtime owner

- Application: `observability`
- Project: `platform`
- Path: `manifests/platform/observability/`
- Bootstrap file: `manifests/bootstrap/applications/platform/observability.yaml`
- Sync wave: `10` 以降

`config-secrets` と infra controller 群の後に同期する。監視基盤は bootstrap 完了条件にしない。

### access owner

公開が必要な場合のみ追加する。

- Application: `observability-access`
- Project: `access`
- Path: `manifests/access/observability/`
- Bootstrap file: `manifests/bootstrap/applications/access/observability-access.yaml`
- Sync wave: `30` 以降

外部公開は初期導入では必須にしない。内部 access のみで始める場合は `observability-internal` surface を追加する。

## Access Contract 案

初期候補は internal only とする。

| Surface ID | Hostname | Exposure | Backend | Publish |
|---|---|---|---|---|
| `observability-internal` | `observability.internal.qroksera.com` | internal | `grafana` / `observability` namespace | CoreDNS + Tailscale Split DNS |

external 公開を行う場合は、MFA / SSO / IP 制限の方針を決めてから `observability-external` を追加する。

## Secret / Config

- Grafana admin password は ExternalSecret で管理する
- datasource / dashboard の非機密設定は runtime owner path の ConfigMap として管理する
- Slack / webhook / SaaS token は初期導入では使わない
- 旧 Grafana Cloud token 名は再利用しない

## Namespace

候補 namespace は `observability` とする。

`monitoring` namespace は旧仕様の identifier であり再利用しない。

## 実装順序

1. `tasks/observability-plan.md` を設計正本として固定する
2. `component-ownership-matrix.md` に `observability` row を追加する
3. `access-surface-matrix.md` に access 候補を追加する
4. `manifests/platform/observability/` の repo-local wrapper を作る（完了）
5. `manifests/bootstrap/applications/platform/observability.yaml` を追加する（完了）
6. internal access が必要なら `access-surfaces.yaml` と `manifests/access/observability/` を追加する
7. `make validate` を green にする
8. live cluster で `observability` Application が `Synced/Healthy` になることを確認する

## 完了条件

- `observability` runtime owner と path が確定している
- access owner の要否が確定している
- secret / config の配置先が決まっている
- `monitoring` legacy identifier を実装 source に戻さない方針が明記されている
- O1 の監視対象を dashboard または health view で確認できる
- `make validate` が green

## Backlog 連携

- 対応 backlog: `B-001`
- 現状態: 設計着手
- 次の実装候補: `observability` runtime owner の repo-local wrapper 作成
