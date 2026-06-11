# Access

この文書は Gateway、HTTPRoute、DNS、Cloudflared、access contract の運用ルールです。

## 方針

- 公開/接続系リソースは `manifests/access/` に置きます。
- hostname / listener / backend / publish は `manifests/contracts/home-lab/access-surfaces.yaml` を正本にします。
- 外部公開は Cloudflared から NGINX Gateway へ集約します。
- TLS は cert-manager のワイルドカード証明書を Gateway に配置します。
- RustFS は console のみ外部公開し、API は外部公開しません。

## 主要 path

| Path | 用途 |
|---|---|
| `manifests/access/gateway/` | 共通 Gateway / listener |
| `manifests/access/cloudflared/` | Cloudflared tunnel |
| `manifests/access/dns/core/` | CoreDNS publish |
| `manifests/access/dns/tailscale/` | Tailnet DNS publish |
| `manifests/access/<app>/` | app ごとの HTTPRoute |
| `manifests/contracts/home-lab/access-surfaces.yaml` | access surface 正本 |

## HTTPRoute 追加

`manifests/access/<app>/` に HTTPRoute を追加し、対応する access surface annotation を付けます。

```yaml
metadata:
  annotations:
    contracts.k8s-myhome.local/access-surface: <app>-internal
```

access owner が新規の場合は `manifests/bootstrap/applications/access/<app>-access.yaml` も追加します。

## Cloudflared

Cloudflared の origin は Gateway に統一します。

```yaml
service: https://nginx-gateway-nginx.nginx-gateway.svc.cluster.local:443
originRequest:
  originServerName: <hostname>
  httpHostHeader: <hostname>
  noTLSVerify: false
```

`originServerName` と `httpHostHeader` は公開ホスト名と一致させます。

## TLS

Gateway が参照する証明書は `nginx-gateway` namespace に置きます。
外部公開はワイルドカード証明書、内部公開は hostname ごとの個別証明書を使います。

| Certificate | Hostname |
|---|---|
| `wildcard-external` | `*.qroksera.com` |
| `argocd-internal` | `argocd.internal.qroksera.com` |
| `harbor-internal` | `harbor.internal.qroksera.com` |
| `cooklog-internal` | `cooklog.internal.qroksera.com` |
| `api-hub-internal` | `api-hub.internal.qroksera.com` |
| `hitomi-upload-viewer-internal` | `hitomi-upload-viewer.internal.qroksera.com` |
| `observability-internal` | `observability.internal.qroksera.com` |

cert-manager 系リソースは `manifests/infrastructure/security/cert-manager/` に集約します。

## 確認コマンド

```bash
kubectl get gateway -A
kubectl get httproute -A
kubectl describe httproute <route-name> -n <namespace>
kubectl get certificate -A
kubectl describe certificate <name> -n <namespace>
kubectl logs -n cloudflared deploy/cloudflared --since=10m
```
