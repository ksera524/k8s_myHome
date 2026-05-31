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
| argocd | `Application/argocd-core` -> `manifests/platform/argocd-config/` | `Application/argocd-access` -> `manifests/access/argocd/` | `Application/argocd-core` | `Application/argocd-access` | `manifests/platform/argocd-config/` | `manifests/access/argocd/` | yes | external / internal route は `argocd-access`、internal DNS publish は `dns-core` が担当する |
| harbor | `Application/harbor` -> `manifests/platform/harbor/` | `Application/harbor-access` -> `manifests/access/harbor/` | `Application/harbor` | `Application/harbor-access` | `manifests/platform/harbor/` | `manifests/access/harbor/` | yes | current repo では runtime/access split が成立済み。cleanup CronJob は runtime owner、`HTTPRoute` / `ClientSettingsPolicy` / hostname publication は access owner。`node-mutations/` は opt-in overlay |
| rustfs | `Application/rustfs` -> `manifests/platform/rustfs/` | `Application/rustfs-access` -> `manifests/access/rustfs/` | `Application/rustfs` | `Application/rustfs-access` | `manifests/platform/rustfs/` | `manifests/access/rustfs/` | yes | 本体と console 公開を分離。`sandbox-config` が `rustfs-svc` に依存 |
| cloudflared | - | `Application/cloudflared` -> `manifests/access/cloudflared/` | - | `Application/cloudflared` | - | `manifests/access/cloudflared/` | no | access plane 専用 owner |
| gateway shared listeners | - | `Application/gateway-shared` -> `manifests/access/gateway/` | - | `Application/gateway-shared` | - | `manifests/access/gateway/` | no | shared access-plane owner。`Gateway` resource / listener 基盤のみを所有し、service ごとの route は持たない |
| coredns host overrides | - | `Application/dns-core` -> `manifests/access/dns/core/` | - | `Application/dns-core` | - | `manifests/access/dns/core/` | no | `harbor` / `argocd` / internal app host の CoreDNS publish を担当 |
| tailscale split DNS | - | `Application/dns-tailscale` -> `manifests/access/dns/tailscale/` | - | `Application/dns-tailscale` | - | `manifests/access/dns/tailscale/` | no | internal hostname の Tailnet 向け公開面 |
| blog | `Application/blog` -> `manifests/apps/blog/` | `Application/blog-access` -> `manifests/access/blog/` | `Application/blog` | `Application/blog-access` | `manifests/apps/blog/` | `manifests/access/blog/` | yes | current repo で workload-only と external route 分離が成立済み |
| cooklog | `Application/cooklog` -> `manifests/apps/cooklog/` | `Application/cooklog-access` -> `manifests/access/cooklog/` | `Application/cooklog` | `Application/cooklog-access` | `manifests/apps/cooklog/` | `manifests/access/cooklog/` | yes | internal route と DNS publish を access owner が担当 |
| api-hub | `Application/api-hub` -> `manifests/apps/api-hub/` | `Application/api-hub-access` -> `manifests/access/api-hub/` | `Application/api-hub` | `Application/api-hub-access` | `manifests/apps/api-hub/` | `manifests/access/api-hub/` | yes | NodePort `32001` は runtime owner、internal route は access owner |
| hitomi-upload-viewer | `Application/hitomi-upload-viewer` -> `manifests/apps/hitomi-upload-viewer/` | `Application/hitomi-upload-viewer-access` -> `manifests/access/hitomi-upload-viewer/` | `Application/hitomi-upload-viewer` | `Application/hitomi-upload-viewer-access` | `manifests/apps/hitomi-upload-viewer/` | `manifests/access/hitomi-upload-viewer/` | yes | internal 公開の owner 分離が current repo で成立済み |
| hitomi | `Application/hitomi` -> `manifests/apps/hitomi/` | - | `Application/hitomi` | - | `manifests/apps/hitomi/` | - | no | workload-only。`SELENIUM_COMMAND_EXECUTOR` は owner-local non-secret config として runtime owner に残す |
| hitomi-pdf | `Application/hitomi-pdf` -> `manifests/apps/hitomi-pdf/` | - | `Application/hitomi-pdf` | - | `manifests/apps/hitomi-pdf/` | - | no | workload-only。`api-hub.internal` と `sandbox-config` に依存 |
| home-camera | `Application/home-camera` -> `manifests/apps/home-camera/` | - | `Application/home-camera` | - | `manifests/apps/home-camera/` | - | no | workload-only。RTSP URL は owner-local non-secret config として runtime owner path に残す |
| selenium | `Application/selenium` -> `manifests/apps/selenium/` | - | `Application/selenium` | - | `manifests/apps/selenium/` | - | no | shared tooling workload。`tools` namespace 常駐 |
| sandbox-config | `Application/sandbox-config` -> `manifests/platform/shared-config/sandbox/` | - | `Application/sandbox-config` | - | `manifests/platform/shared-config/sandbox/` | - | no | shared config owner。複数 workload 参照のため platform 配下に収束済み |
| monitoring (legacy) | `Application/monitoring` -> `grafana/k8s-monitoring` + `manifests/monitoring/` | - | `PH6 で削除` | - | `manifests/monitoring/` | - | no | target state では owner を持たせず除去 |

## メモ

- `Target Runtime Owner` / `Target Access Owner` の命名は PH0 合意済みの canonical 名称とし、PH2 では file 配置 / sync wave / render 単位を実装確定する
- `Runtime Path` / `Access Path` は target state の canonical path。抽出順と sync wave は `ph2-gitops-topology-normalization.md` の決定を正とする
- `access` owner は `service access` と `shared access plane` の 2 層に固定する
- Git が追跡しない workspace-local empty dir はこの表の current owner 判定に含めず、tracked path / stale reference / reinflow check を正とする
