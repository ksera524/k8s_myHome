# Access Surface Matrix

## 目的

- hostname / listener / backend / tunnel / DNS publish の関係を 1 枚で追跡する
- `Gateway`, `Cloudflared`, `CoreDNS`, `Tailscale Split DNS` の二重管理をなくす

## 使い方

- PH0 では surface の棚卸しに使う
- PH4 では `access-surfaces.yaml` の初期値設計に使う
- PH5 では contract 逸脱検出ルールの入力に使う

| Surface ID | Hostname | Exposure | Backend Service | Backend Namespace | Gateway Listener | Cloudflared | CoreDNS | Tailscale Split DNS | Current Owner | Target Access Path | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| argocd-external | `argocd.qroksera.com` | external | `argocd-server` | `argocd` | `https-argocd-external` | yes | no | no | `Application/argocd-access`<br>`Application/cloudflared`<br>`Application/gateway-shared` | `manifests/access/argocd/` | external surface。Cloudflared は `nginx-gateway-nginx:443` を共通 backend にしている |
| argocd-internal | `argocd.internal.qroksera.com` | internal | `argocd-server` | `argocd` | `https-internal` | no | yes | no | `Application/argocd-access`<br>`Application/dns-core`<br>`Application/gateway-shared` | `manifests/access/argocd/` | internal publish は CoreDNS-only。Tailnet 向け split DNS には載せない |
| harbor-external | `harbor.qroksera.com` | external | `harbor-core` / `harbor-portal` | `harbor` | `https-harbor-external` | yes | yes | no | `Application/harbor-access`<br>`Application/cloudflared`<br>`Application/dns-core`<br>`Application/gateway-shared` | `manifests/access/harbor/` | 外部 hostname だが CoreDNS でも固定解決している。cleanup CronJob など runtime automation の到達先には使わない |
| harbor-internal | `harbor.internal.qroksera.com` | internal | `harbor-core` / `harbor-portal` | `harbor` | `https-internal` | no | yes | no | `Application/harbor-access`<br>`Application/dns-core`<br>`Application/gateway-shared` | `manifests/access/harbor/` | internal publish は CoreDNS-only。Cloudflared / Tailscale Split DNS は持たない。runtime automation の到達先は別途 runtime-local endpoint として扱う |
| rustfs-console | `rustfs.qroksera.com` | external | `rustfs-svc` | `rustfs` | `https-rustfs` | yes | no | no | `Application/rustfs-access`<br>`Application/cloudflared`<br>`Application/gateway-shared` | `manifests/access/rustfs/` | RustFS 本体は Helm owner、console 公開だけ別 owner |
| blog-external | `blog.qroksera.com` | external | `blog` | `sandbox` | `https-blog-external` | yes | no | no | `Application/blog-access`<br>`Application/cloudflared`<br>`Application/gateway-shared` | `manifests/access/blog/` | route / tunnel / listener は access owner に分離済み |
| cooklog-internal | `cooklog.internal.qroksera.com` | internal | `cooklog` | `sandbox` | `https-internal` | no | yes | yes | `Application/cooklog-access`<br>`Application/dns-core`<br>`Application/dns-tailscale`<br>`Application/gateway-shared` | `manifests/access/cooklog/` | internal route + CoreDNS + Tailnet split DNS の 3 系統管理 |
| api-hub-internal | `api-hub.internal.qroksera.com` | internal | `api-hub` | `sandbox` | `https-internal` | no | yes | yes | `Application/api-hub-access`<br>`Application/dns-core`<br>`Application/dns-tailscale`<br>`Application/gateway-shared` | `manifests/access/api-hub/` | internal route と DNS を統合対象。Service 自体は NodePort `32001` も持つ |
| hitomi-upload-viewer-internal | `hitomi-upload-viewer.internal.qroksera.com` | internal | `hitomi-upload-viewer` | `sandbox` | `https-internal` | no | yes | yes | `Application/hitomi-upload-viewer-access`<br>`Application/dns-core`<br>`Application/dns-tailscale`<br>`Application/gateway-shared` | `manifests/access/hitomi-upload-viewer/` | internal route と DNS を統合対象 |
| observability-internal | `observability.internal.qroksera.com` | internal | `victoria-metrics` | `observability` | `https-internal` | no | yes | yes | `Application/observability-access`<br>`Application/dns-core`<br>`Application/dns-tailscale`<br>`Application/gateway-shared` | `manifests/access/observability/` | B-001 初期実装。Grafana / alerting は後続で、外部公開は SSO / 制限方針を決めるまで追加しない |

## メモ

- `Surface ID` が `access-surfaces.yaml` の canonical entry name になる
- service ごとの route / policy は `manifests/access/<service>/` の `service access` owner が持ち、listener 基盤は `manifests/access/gateway/` の `gateway-shared` が持つ
- hostname の publish は `cloudflared`, `dns-core`, `dns-tailscale` の `shared access plane` owner が持つ
- access URL は原則 `Surface ID + hostname + scheme` から導出し、独立した cluster contract key は持たない
- Harbor cleanup CronJob のような runtime automation の in-cluster Service endpoint は access surface に含めず、owner local config として扱う
- Cloudflared tunnel ID など surface 横断の shared access-plane metadata は `access-surfaces.yaml` 配下の `shared` entry で管理する
- external surface の tunnel publish は current repo では `manifests/access/cloudflared/cloudflared-config.yaml` で一括管理されている
- internal surface の listener は `https-internal` 共有で、route / CoreDNS / Tailnet split DNS はそれぞれ `access/**` 配下の shared owner / service owner が持つ
