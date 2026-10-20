# アクセス経路と公開の追加

経路の照合元は [access-surfaces.yaml](../manifests/contracts/home-lab/access-surfaces.yaml)、
実リソースは [access/](../manifests/access/) です。contract の変更だけでは DNS や Route は生成されません。

```mermaid
flowchart LR
  Internet[Internet: Harbor] --> CF[Cloudflare Tunnel]
  CF --> Tunnel[cloudflared]
  Tunnel --> GW[NGINX Gateway :443]
  Client[LAN / Tailnet 端末] --> GW
  Client -. 名前解決 .-> DNS[Split DNS 192.168.122.101]
  GW --> Route[HTTPRoute]
  Route --> Service[Service / Pod]
```

## 利用する URL

通常の内部 URL は `https://<名前>.internal.qroksera.com` です。
名前は `argocd`、`harbor`、`rustfs`、`blog`、`cooklog`、`api-hub`、`hitomi-upload-viewer`、
`observability`、`rsshub`、`grafana` が宣言されています。
VMUI は `https://observability.internal.qroksera.com/vmui/` です。

[Cloudflared 設定](../manifests/access/cloudflared/cloudflared-config.yaml) が転送する外部 hostname は
`harbor.qroksera.com` のみで、残りは catch-all の 404 になります。
ArgoCD / RustFS / Blog の外部 hostname 用 Route 自体は残っているため、
「Tunnel に登録していない」ことを「Gateway からも接続できない」と混同しないでください。

RustFS の Gateway backend は console の 9001 のみです。S3 の 9000 はクラスタ内で api-hub などが利用します。
console の `/` は GET / HEAD のリダイレクトと POST / Authorization 付き GET の転送を
[HTTPRoute](../manifests/access/rustfs/manifest.yaml) で分岐しています。

## DNS・TLS・外部設定

| 対象 | 宣言元・役割 |
|---|---|
| 共通 Gateway | [gateway.yaml](../manifests/access/gateway/gateway.yaml)、LB `192.168.122.100` |
| クラスタ内 DNS | [CoreDNS](../manifests/access/dns/core/coredns-configmap.yaml) |
| Tailnet 向け DNS | [Split DNS](../manifests/access/dns/tailscale/manifest.yaml)、LB `192.168.122.101` |
| TLS | [cert-manager 設定](../manifests/infrastructure/security/cert-manager/)、DNS-01、外部 wildcard と内部個別証明書 |
| Tunnel | [cloudflared](../manifests/access/cloudflared/)、Gateway:443 へ TLS 検証付きで転送 |

Gateway の証明書 Secret は `nginx-gateway` namespace に置きます。
内部 hostname でも公開 ACME issuer の DNS-01 を使っています。「内部 URL だから独自 CA を端末へ追加する」とは限りません。

Tailnet 側では `192.168.122.0/24` の subnet route 承認、端末での route 受け入れ、
`internal.qroksera.com` の Split DNS を `.101` に向ける設定が必要です。
DNS の UDP/TCP 53、Gateway の TCP 443（HTTP redirect を使うなら 80）の到達性も確認します。
Harbor internal は contract 上 Tailscale Split DNS の publish 対象ではなく、CoreDNS 側に登録されています。
必要なクライアントの名前解決は個別に確認してください。

GitHub OAuth App の callback は ArgoCD の URL と `/api/dex/callback` を一致させます。
Cloudflare の DNS と Tunnel の紐付け、Tailnet ACL、OAuth App の設定はこのリポジトリから自動反映されません。

## 新しく到達可能な API を追加する手順

1. 公開範囲（クラスタ内 / LAN・Tailnet / Internet）、hostname、backend Service と port、呼び出し元を決めます。
2. [アプリ配布](app-delivery.md) に従って workload / Service / Secret を追加します。
   クラスタ内 Service DNS のみで利用するなら Gateway / hostname の追加は不要です。
3. hostname を使う場合は contract の surface を追加します。`backend`、`gatewayListener`、各 `publish` を指定します。
4. `access/<app>/` に HTTPRoute と Kustomization を追加します。
   annotation `contracts.k8s-myhome.local/access-surface` を surface 名に合わせます。
   `parentRefs.sectionName`、hostname、backend の **Service port** を照合します。
5. 必要な Gateway listener と Certificate を追加します。証明書は cert-manager 配下に置きます。
6. 必要な CoreDNS / Split DNS の hosts と surface annotation を更新します。
   外部公開なら cloudflared の catch-all より前へ追加し、`originServerName` / `httpHostHeader` を hostname と一致させます。
   ConfigMap の変更時は Pod template も変更し、新しい設定を読み込ませます。
7. 新しい access Application を `bootstrap/applications/access/` に作り、Kustomization と [一覧](diagrams/app-of-apps-sync-wave.md) に登録します。
8. [NetworkPolicy](network-policy.md) の受信先・送信元と **Pod の待受 port** を確認し、必要な許可を追加します。
9. 静的検証後、Secret / workload の準備、公開経路の同期、クライアントからの実操作を順に確認します。

Service が 80 → 8080 なら HTTPRoute は 80、NetworkPolicy は 8080 です。
既存 HTTPRoute の PathPrefix 内で API のパスだけを追加する場合、接続先・port・公開範囲が変わらなければ
新しい Route は通常不要です。認証・認可はアプリ側で実装します。

## 反映後の確認

```bash
kubectl -n argocd get applications
kubectl -n nginx-gateway get gateway,svc,certificate
kubectl -n <namespace> describe httproute <route-name>
kubectl -n <namespace> get svc,endpointslices
```

Gateway の Programmed、HTTPRoute の Accepted / ResolvedRefs、Certificate の Ready を確認します。
利用端末で DNS と HTTPS、ログイン後の主要操作を確認し、通信制限を追加した場合は拒否される経路も実測します。
初回公開や依存変更の順序を、別 Application の wave だけに依存させないでください。
