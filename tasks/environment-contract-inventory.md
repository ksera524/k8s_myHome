# Environment Contract Inventory

## 目的

- 環境固有の非機密値がどこに散っているかを可視化する
- `cluster-contract.yaml` と `access-surfaces.yaml` の target 参照先を決める

## 使い方

- PH0 では current location の棚卸しに使う
- PH4 では target contract ref と移行優先順位を確定する
- PH5 では contract 未反映値の検出ルール設計に使う

| Category | Current Literal / Value | Current Locations | Target Contract Ref | Secret / Local | Priority | Notes |
|---|---|---|---|---|---|---|
| external domain | `qroksera.com` | `manifests/infrastructure/networking/nginx-gateway-fabric/gateway/gateway.yaml`<br>`manifests/apps/cloudflared/cloudflared-config.yaml`<br>`manifests/apps/blog/manifest.yaml`<br>`manifests/apps/argocd/manifest.yaml`<br>`manifests/apps/rustfs/manifest.yaml`<br>`manifests/infrastructure/gitops/harbor/harbor-routes.yaml`<br>`manifests/platform/argocd-config/argocd-config.yaml` | `global.domain.external` | non-secret | high | external hostname の基底 |
| internal domain | `internal.qroksera.com` | `manifests/apps/argocd/manifest.yaml`<br>`manifests/apps/api-hub/manifest.yaml`<br>`manifests/apps/cooklog/manifest.yaml`<br>`manifests/apps/hitomi-upload-viewer/manifest.yaml`<br>`manifests/infrastructure/networking/coredns/coredns-configmap.yaml`<br>`manifests/infrastructure/networking/tailscale-split-dns/manifest.yaml`<br>`manifests/infrastructure/security/cert-manager/wildcard-internal-cert.yaml` | `global.domain.internal` | non-secret | high | internal hostname の基底 |
| host network CIDR | `192.168.122.0/24` | `automation/settings.toml`<br>`automation/settings.toml.example`<br>`manifests/core/networkpolicies.yaml`<br>`manifests/infrastructure/networking/tailscale-operator/connector.yaml` | `network.host.cidr` | non-secret | high | cluster edge と Tailnet connector が同じ値を参照 |
| node IPs | `192.168.122.10`, `192.168.122.11`, `192.168.122.12` | `automation/settings.toml`<br>`automation/settings.toml.example`<br>`automation/platform/platform-deploy.sh` | `network.nodes.controlPlane`, `network.nodes.workers[]` | non-secret | medium | settings と deploy script default が重複 |
| pod/service CIDR | `10.244.0.0/16`, `10.96.0.0/12` | `automation/settings.toml.example` | `network.podCIDR`, `network.serviceCIDR` | non-secret | low | 現状は settings 側中心で manifest 直参照は少ない |
| MetalLB range | `192.168.122.100-192.168.122.150` | `automation/settings.toml`<br>`automation/settings.toml.example`<br>`manifests/infrastructure/networking/metallb/metallb-ipaddress-pool.yaml` | `network.metallb.range` | non-secret | high | automation と manifest の二重管理 |
| gateway LB IP | `192.168.122.100` | `manifests/bootstrap/app-of-apps.yaml` (`nginx-gateway-fabric` Helm inline values)<br>`manifests/infrastructure/networking/coredns/coredns-configmap.yaml` | `network.serviceIPs.gateway` | non-secret | high | canonical service IP。Harbor/ArgoCD など gateway 配下 surface はこの値から到達先が導出される |
| tailscale split DNS LB IP | `192.168.122.101` | `manifests/infrastructure/networking/tailscale-split-dns/manifest.yaml`<br>`automation/settings.toml` (`ingress_lb_ip`)<br>`automation/settings.toml.example` (`ingress_lb_ip`) | `network.serviceIPs.tailscaleSplitDNS` | non-secret | high | canonical service IP。旧 `ingress_lb_ip` は rename/remove 対象 |
| NFS server | `192.168.122.1` | `manifests/bootstrap/app-of-apps.yaml` (`nfs-subdir-external-provisioner` Helm inline values) | `storage.nfs.server` | non-secret | high | NFS provisioner の正本 |
| NFS path | `/mnt/k8s-storage/nfs-share` | `manifests/bootstrap/app-of-apps.yaml`<br>`automation/settings.toml` (`/data/nfs-share`)<br>`automation/settings.toml.example` (`/data/nfs-share`) | `storage.nfs.path` | non-secret | high | settings と manifest の path が一致していない |
| external storage class | `nfs-external` | `manifests/bootstrap/app-of-apps.yaml`<br>`manifests/bootstrap/applications/user-apps/rustfs-app.yaml` | `storage.classes.external` | non-secret | high | Harbor / RustFS 両方が依存 |
| local storage classes | `local-storage`, `local-ssd-storage`, `local-path` | `manifests/core/kustomization.yaml`<br>`manifests/infrastructure/storage/local-path/local-path-provisioner.yaml`<br>`automation/settings.toml`<br>`automation/settings.toml.example` | `storage.classes.local` | non-secret | medium | 3 系統の naming が共存 |
| ArgoCD external URL | `https://argocd.qroksera.com` | `manifests/platform/argocd-config/argocd-config.yaml`<br>`manifests/apps/argocd/manifest.yaml`<br>`manifests/apps/cloudflared/cloudflared-config.yaml`<br>`manifests/infrastructure/networking/nginx-gateway-fabric/gateway/gateway.yaml` | `derive from access-surfaces.yaml#argocd-external (scheme=https)` | non-secret | medium | URL は独立 key を持たず、surface から導出する |
| Harbor external URL | `https://harbor.qroksera.com` | `manifests/bootstrap/app-of-apps.yaml`<br>`manifests/infrastructure/gitops/harbor/harbor-image-cleanup-cronjob.yaml`<br>`manifests/platform/secrets/external-secrets/external-secret-resources.yaml` | `derive from access-surfaces.yaml#harbor-external (scheme=https)` | non-secret | high | Harbor が外部へ広告する正規 URL。現状は app URL と API / secret template が混在しており、cleanup CronJob も参照しているが、target-state では cleanup CronJob を internal Service へ切り離す |
| Harbor registry auth hosts | `harbor.qroksera.com`, `192.168.122.100` | `manifests/platform/argocd-config/harbor-unified-registry-secrets.yaml`<br>`manifests/platform/secrets/external-secrets/external-secret-resources.yaml` | `derive from access-surfaces.yaml#harbor-external + network.serviceIPs.gateway` | non-secret | high | image pull/push 認証用の派生値。hostname と gateway IP の dual auth を持つが、cleanup CronJob 共有用途には使わない |
| Harbor internal host alias | `harbor.internal.qroksera.com -> 192.168.122.100` | `manifests/platform/ci-cd/github-actions/runners-appset.yaml` | `derive from access-surfaces.yaml#harbor-internal + network.serviceIPs.gateway` | non-secret | medium | runner 専用派生値。surface と gateway service IP から導出する。runtime automation 用 endpoint とは別責務 |
| Cloudflared tunnel ID | `9fded92e-4b5b-4b7e-b86d-2a10b8bc0e16` | `manifests/apps/cloudflared/cloudflared-config.yaml` | `access-surfaces.yaml#shared.cloudflared.tunnelId` | non-secret | medium | environment 固有だが secret ではない。shared access-plane metadata として管理 |
| RustFS sandbox endpoint | `http://rustfs-svc.rustfs.svc:9000` | `manifests/apps/sandbox-config/manifest.yaml` | `manifests/platform/shared-config/sandbox/` | non-secret | medium | shared app config。contract ではなく `platform/shared-config` へ再分類する |
| RustFS region | `us-east-1` | `manifests/apps/sandbox-config/manifest.yaml` | `manifests/platform/shared-config/sandbox/` | non-secret | low | sandbox shared config。contract へ昇格させない |
| API Hub internal URL | `https://api-hub.internal.qroksera.com` | `manifests/apps/hitomi-upload-viewer/manifest.yaml`<br>`manifests/apps/hitomi-pdf/manifest.yaml` | `derive from access-surfaces.yaml#api-hub-internal (scheme=https)` | non-secret | medium | app 間依存のため canonical internal surface から導出する |
| API Hub NodePort | `32001` | `manifests/apps/api-hub/manifest.yaml` | `apps.apiHub.service.nodePort` | non-secret | low | access plane からは外れるが固定値 |
| Selenium endpoint | `http://selenium-standalone-chrome.tools:4444/wd/hub` | `manifests/apps/hitomi/manifest.yaml` | `owner-local non-secret config (manifests/apps/hitomi/)` | non-secret | medium | 現状は `hitomi` 単独利用。shared-config ではなく runtime owner path に残す |
| home-camera RTSP URL | `rtsp://s5kVuizVreFu2SxK:0FnaKGTm2bGgqxK2@192.168.10.15/live0` | `manifests/apps/home-camera/manifest.yaml` | `owner-local non-secret config (manifests/apps/home-camera/)` | non-secret | medium | app 固有の非機密設定。contract / shared-config / secret へ昇格させない |

## メモ

- `Current Locations` は PH0 で grep 結果を追記して精緻化する
- secret 値そのものはこの台帳に入れず、ESO / `settings.toml` 側の責務に残す
- access URL / host alias / auth host のような surface 由来値は独立 key にせず、`access-surfaces.yaml` と `network.serviceIPs.*` から導出する
- Harbor cleanup CronJob のような runtime-local endpoint は contract key にせず、owner local configuration として扱う
- app 固有の非機密設定は runtime owner path の owner-local non-secret config に残し、複数 workload が共有する場合のみ `shared-config` へ昇格させる
- `network.serviceIPs.gateway` と `network.serviceIPs.tailscaleSplitDNS` を canonical とし、旧 `ingress_lb_ip` は rename/remove 対象として扱う
