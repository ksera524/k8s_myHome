# Component Ownership Matrix

## 目的

- 主要コンポーネントの current owner と target owner を 1 枚で追跡する
- `runtime + access` pair の要否と split-owner 例外を明確化する

## 使い方

- PH0 では current / target の責務整理に使う
- PH2 では path / Application 名 / owner を確定する
- PH6 では削除対象 legacy の最終確認に使う

## 管理ルール

- 1 行 = 1 component
- `Target Runtime Owner` と `Target Access Owner` は最終的に 1 つずつに収束させる
- `Split Allowed` は `runtime + access` pair のみ `yes` とし、それ以外は `no`

| Component | Current Runtime Owner | Current Access Owner | Target Runtime Owner | Target Access Owner | Runtime Path | Access Path | Split Allowed | Notes |
|---|---|---|---|---|---|---|---|---|
| argocd | `Application/argocd-core` -> `manifests/platform/argocd-config` | `argocd-external-app.yaml` -> `manifests/apps/argocd` | `bootstrap/applications/platform/argocd-core` | `bootstrap/applications/access/argocd-access` | `manifests/platform/argocd-config/` | `manifests/access/argocd/` | yes | 現在の route file は external / internal を同居。CoreDNS 側 host override も別 owner |
| harbor | `Application/harbor` (app-of-apps, Helm chart) | `Application/harbor-patch` -> `manifests/infrastructure/gitops/harbor` | `bootstrap/applications/platform/harbor` | `bootstrap/applications/access/harbor-access` | `manifests/platform/harbor/` | `manifests/access/harbor/` | yes | target では repo-local wrapper 配下に Harbor chart values と cleanup CronJob を同居させ、cleanup CronJob は in-cluster Harbor Service を使う。`HTTPRoute` / `ClientSettingsPolicy` / hostname publication は access owner、`node-mutations` は steady-state owner を持たない opt-in overlay として分離する |
| rustfs | `rustfs-app.yaml` (chart `rustfs`) | `rustfs-external-app.yaml` -> `manifests/apps/rustfs` | `bootstrap/applications/platform/rustfs` | `bootstrap/applications/access/rustfs-access` | `manifests/platform/rustfs/` | `manifests/access/rustfs/` | yes | 本体と console 公開を分離。`sandbox-config` が `rustfs-svc` に依存 |
| cloudflared | - | `cloudflared-app.yaml` -> `manifests/apps/cloudflared` | - | `bootstrap/applications/access/cloudflared` | - | `manifests/access/cloudflared/` | no | access plane 専用 owner。現状は `project: apps` だが target は access |
| gateway shared listeners | - | `Application/nginx-gateway-resources` -> `manifests/infrastructure/networking/nginx-gateway-fabric/gateway` | - | `bootstrap/applications/access/gateway-shared` | - | `manifests/access/gateway/` | no | shared access-plane owner。`Gateway` resource / listener 基盤のみを所有し、service ごとの route は持たない |
| coredns host overrides | - | `Application/coredns-config` -> `manifests/infrastructure/networking/coredns` | - | `bootstrap/applications/access/dns-core` | - | `manifests/access/dns/core/` | no | `harbor` / `argocd` / internal app host を現在ここで解決 |
| tailscale split DNS | - | `Application/tailscale-split-dns` -> `manifests/infrastructure/networking/tailscale-split-dns` | - | `bootstrap/applications/access/dns-tailscale` | - | `manifests/access/dns/tailscale/` | no | internal hostname の Tailnet 向け公開面 |
| blog | `blog-app.yaml` -> `manifests/apps/blog` | 同一 owner に route 同居 | `bootstrap/applications/user-apps/blog` | `bootstrap/applications/access/blog-access` | `manifests/apps/blog/` | `manifests/access/blog/` | yes | workload-only 化対象 |
| cooklog | `cooklog-app.yaml` -> `manifests/apps/cooklog` | 同一 owner に route 同居 | `bootstrap/applications/user-apps/cooklog` | `bootstrap/applications/access/cooklog-access` | `manifests/apps/cooklog/` | `manifests/access/cooklog/` | yes | internal route と DNS 依存を access へ寄せる |
| api-hub | `api-hub-app.yaml` -> `manifests/apps/api-hub` | 同一 owner に route 同居 | `bootstrap/applications/user-apps/api-hub` | `bootstrap/applications/access/api-hub-access` | `manifests/apps/api-hub/` | `manifests/access/api-hub/` | yes | NodePort `32001` と internal route を分離 |
| hitomi-upload-viewer | `hitomi-upload-viewer-app.yaml` -> `manifests/apps/hitomi-upload-viewer` | 同一 owner に route 同居 | `bootstrap/applications/user-apps/hitomi-upload-viewer` | `bootstrap/applications/access/hitomi-upload-viewer-access` | `manifests/apps/hitomi-upload-viewer/` | `manifests/access/hitomi-upload-viewer/` | yes | internal 公開の owner 分離 |
| hitomi | `hitomi-app.yaml` -> `manifests/apps/hitomi` | - | `bootstrap/applications/user-apps/hitomi` | - | `manifests/apps/hitomi/` | - | no | workload-only。`SELENIUM_COMMAND_EXECUTOR` は owner-local non-secret config として runtime owner に残す |
| hitomi-pdf | `hitomi-pdf-app.yaml` -> `manifests/apps/hitomi-pdf` | - | `bootstrap/applications/user-apps/hitomi-pdf` | - | `manifests/apps/hitomi-pdf/` | - | no | workload-only。`api-hub.internal` と `sandbox-config` に依存 |
| home-camera | `home-camera-app.yaml` -> `manifests/apps/home-camera` | - | `bootstrap/applications/user-apps/home-camera` | - | `manifests/apps/home-camera/` | - | no | workload-only。RTSP URL は owner-local non-secret config として runtime owner path に残す |
| selenium | `selenium-app.yaml` -> `manifests/apps/selenium` | - | `bootstrap/applications/user-apps/selenium` | - | `manifests/apps/selenium/` | - | no | shared tooling workload。`tools` namespace 常駐 |
| sandbox-config | `sandbox-config-app.yaml` -> `manifests/apps/sandbox-config` | - | `bootstrap/applications/platform/sandbox-config` | - | `manifests/platform/shared-config/sandbox/` | - | no | shared config owner。複数 workload が参照するため `apps/` から platform 配下へ移す |
| monitoring (legacy) | `Application/monitoring` -> `grafana/k8s-monitoring` | - | `PH6 で削除` | - | `manifests/monitoring/` | - | no | target state では owner を持たせず除去 |

## メモ

- `Target Runtime Owner` / `Target Access Owner` の命名は PH0 合意済みの canonical 名称とし、PH2 では file 配置 / sync wave / render 単位を実装確定する
- `Runtime Path` / `Access Path` は target state の canonical path。抽出順と sync wave は `ph2-gitops-topology-normalization.md` の決定を正とする
- `access` owner は `service access` と `shared access plane` の 2 層に固定する
- `manifests/apps/harbor/`, `manifests/apps/monitoring/`, `manifests/apps/postgresql/`, `manifests/apps/slack/`, `manifests/apps/user-up/` は reservation せず削除対象として扱う
