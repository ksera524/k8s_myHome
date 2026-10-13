# Access

この文書は Gateway、HTTPRoute、DNS、Cloudflared、access contract の運用ルールです。

## 方針

- 公開/接続系リソースは `manifests/access/` に置きます。
- hostname / listener / backend / publish は `manifests/contracts/home-lab/access-surfaces.yaml` を正本にします。
- 外部公開は Cloudflared から NGINX Gateway へ集約します。
- TLS は cert-manager の証明書を Gateway に配置します（外部はワイルドカード、内部は個別証明書）。
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

## 新しく到達可能な API を追加する手順

### 1. 公開範囲と通信経路を決める

最初に hostname、利用者、接続元 Namespace / Pod ラベル、Service port、
実際の Pod の待受ポート（targetPort）、依存先を記録します。

| 利用範囲 | 通信経路 | 追加する入口 |
|---|---|---|
| クラスタ内のみ | 呼び出し元 Pod → ClusterIP Service → API Pod | Service と NetworkPolicy |
| LAN / Tailnet 内 | 利用者 → 内部 DNS → Gateway → API Pod | 内部 hostname、証明書、HTTPRoute |
| インターネット | 利用者 → Cloudflare Tunnel → cloudflared → Gateway → API Pod | 外部 hostname、Tunnel の公開設定、HTTPRoute |

既存の api-hub などに HTTP パスだけを追加し、hostname・ポート・接続元・依存先が変わらず、
既存 HTTPRoute の PathPrefix に含まれる場合は、新しい Service / HTTPRoute / NetworkPolicy は不要です。
アプリ側の認証・認可と API 実装を追加し、イメージ更新後に動作確認します。
NetworkPolicy は HTTP パスや利用者の権限を判別しないため、認証・認可の代わりにはなりません。

RustFS の操作は原則 api-hub の BFF 経由にします。新しい利用アプリごとに RustFS:9000 を
許可する必要はありません。presigned URL をクライアントに渡して直接転送させる変更は、
現在の「api-hub だけが S3 API に接続できる」構成とは異なるため、別途経路を設計します。

### 2. 新しいサービスなら workload と Service を追加する

- `manifests/apps/<app>/` に Deployment / ClusterIP Service / `kustomization.yaml` を追加します。
- Service selector と Pod ラベル、Service port と targetPort の対応を確認します。
  新規 API の通常の入口に NodePort は追加しません。
- `manifests/bootstrap/applications/user-apps/<app>-app.yaml` を追加し、
  同ディレクトリの `kustomization.yaml` に登録します。既存例は `api-hub-app.yaml` です。
- 新規 Namespace が必要なら `manifests/core/namespaces.yaml` に追加し、
  使用する AppProject の destination にも含まれることを確認します。
- 認証情報は `manifests/platform/secrets/external-secrets/` に定義し、workload から Secret を参照します。

イメージ更新と workload の手順は [App Delivery](app-delivery.md) を参照してください。

### 3. hostname を公開する場合は contract と access を追加する

クラスタ内の Service DNS だけで利用する API は、この節の追加は不要です。

1. `manifests/contracts/home-lab/access-surfaces.yaml` に surface を追加します。
   hostname / backend / gatewayListener / publish を指定します。contract は設定の正本であり、
   HTTPRoute や DNS を自動生成するものではないため、以下の実体も更新します。
2. `manifests/access/<app>/` に HTTPRoute と `kustomization.yaml` を追加します。
   surface annotation、hostname、parentRefs の listener、backendRefs の Service 名と **Service port** を一致させます。
   通常は API と同じ Namespace に HTTPRoute を置きます。HTTP → HTTPS redirect も既存例に合わせます。
3. `manifests/access/gateway/gateway.yaml` に必要な HTTPS listener を追加します。
   既存 listener を使える場合は追加不要です。証明書の対象 hostname と allowedRoutes も確認します。
4. 内部 hostname の Certificate は `manifests/infrastructure/security/cert-manager/internal-certificates.yaml` に追加します。
   外部 hostname は既存の `*.qroksera.com` 証明書でカバーされるか確認します。
5. 内部公開は、利用範囲に応じて `manifests/access/dns/core/coredns-configmap.yaml` と
   `manifests/access/dns/tailscale/manifest.yaml` の hosts と access-surfaces annotation を更新します。
   Tailnet 側の Split DNS と Gateway IP への経路も確認します。
6. 外部公開は `manifests/access/cloudflared/cloudflared-config.yaml` に hostname を追加します。
   origin は既存と同じ Gateway:443 とし、`originServerName` / `httpHostHeader` を hostname に合わせます。
   catch-all の `http_status:404` より前に配置し、access-surfaces annotation も更新します。
   Cloudflare 側の DNS が対象 Tunnel に紐付いていることも確認します。ConfigMap の追加だけでは DNS は作成されません。
7. 新しい access owner は `manifests/bootstrap/applications/access/<app>-access.yaml` に定義し、
   同ディレクトリの `kustomization.yaml` に登録します。既存例は `api-hub-access.yaml` です。

Application の `targetRevision` は `HEAD`、runtime は wave 12、access は wave 13 を既存例の基準にします。
新しい Application の追加や wave の変更は [Sync Wave 図](diagrams/app-of-apps-sync-wave.md) に反映します。

### 4. 宛先 API の NetworkPolicy を追加する

現行のポリシー owner は `core` です。`manifests/core/networkpolicies.yaml` に、
**宛先 Namespace** のポリシーを追加します。新しい YAML に分ける場合は `core/kustomization.yaml` に登録します。
現在は全 Namespace に一律の default-deny があるわけではなく、
Ingress ポリシーに選択されていない Pod は原則として受信が許可されます。

以下は `sandbox` の `app=sample-api`、Pod の待受ポート 8080 を、
共有 Gateway の NGINX Pod からだけ許可する例です。名前・Namespace・ラベル・ポートを実体に合わせて変更します。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: sample-api-from-gateway
  namespace: sandbox
spec:
  podSelector:
    matchLabels:
      app: sample-api
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: nginx-gateway
          podSelector:
            matchLabels:
              app.kubernetes.io/name: nginx-gateway-nginx
              gateway.networking.k8s.io/gateway-name: nginx-gateway
      ports:
        - protocol: TCP
          port: 8080
```

`namespaceSelector` と `podSelector` は同じ peer に書くと AND 条件になります。
別々のリスト要素にすると OR 条件になり、許可対象が広がります。
NetworkPolicy の port は **Pod の待受ポート**です。Service が 80 → 8080 の場合、
HTTPRoute は 80、NetworkPolicy は 8080 を指定します。

クラスタ内から直接呼ぶ場合は、実際の呼び出し元 Namespace と Pod ラベルを同様に限定した peer を追加します。
API が DB や別 API に接続する場合は、その依存先の受信ポリシーも確認します。
送信元に Egress 制限がある場合は送信側の許可も必要です。今回は一律の Egress 制限は導入していません。
監視の scrape 元などが必要なら、その通信元とポートも明示します。

既存の広い許可ルールがないかも確認します。NetworkPolicy の許可は合算されるため、
狭いルールを追加しても別の全許可ルールは打ち消せません。
Cloudflared → Gateway → API の経路では、API から見た接続元は NGINX Pod です。
API 側で Cloudflared や Cloudflare の公開 IP を許可元に追加しません。
共有 Gateway 全体を Cloudflared 限定にすると内部公開 API に影響するため、入口制限の変更は別途設計します。

### 5. 検証して GitOps で反映する

```bash
nix develop --command bash automation/scripts/ci/validate.sh
git diff --check
```

workload と access の変更は [App Delivery](app-delivery.md) に沿って分け、Git に反映します。
初めて公開する API は、必要な Secret・宛先のポリシー・workload の準備を先に確認し、
HTTPRoute / DNS / Cloudflared の公開を後に行います。
既存 API の許可元を変更する場合は、新しい許可を同期して接続確認後に古い許可を削除します。
独立した Application の更新順は wave だけに依存せず、各段階の同期を確認します。

次のプレースホルダーは実際の名前に置き換えます。

```bash
kubectl get applications -n argocd
kubectl get ds kube-network-policies -n kube-system
kubectl get pods,svc,endpointslices -n <namespace>
kubectl get networkpolicy -n <namespace>
kubectl describe httproute <route-name> -n <namespace>
kubectl get gateway -n nginx-gateway
kubectl get certificate -n nginx-gateway
```

API の Application が Synced / Healthy、controller が全ノード Ready、
HTTPRoute の Accepted / ResolvedRefs と Gateway の Programmed が True、証明書が Ready であることを確認します。

### 6. 許可通信と拒否通信を実測する

| 確認 | 合格条件 |
|---|---|
| 正規の入口 | 内部なら LAN / Tailnet、外部なら Cloudflare 経由で想定した応答を得る |
| 認証と実操作 | 認証後の主要操作まで成功する。401 / 403 だけでは操作成功とはしない |
| 呼び出し元制限 | 無関係な Pod、別 Namespace の同名ラベルの Pod から直接接続できない |
| 宛先制限 | Service IP と Pod IP の両方で拒否を確認し、許可していないポートも試す |
| 既存経路 | ArgoCD / Harbor / RustFS console と api-hub 経由の S3 操作を維持する |

拒否試験は通常の Pod ネットワークから行い、複数ノードで確認します。
`kubectl port-forward` やノードからの接続だけでは Pod 間の NetworkPolicy 検証になりません。
HTTP 403 はアプリまで到達した結果であり、NetworkPolicy による遮断と区別します。
テスト用 Pod に本番 Service と同じラベルを付けるとトラフィックを受ける場合があるため、
正規の呼び出し元の確認には実アプリ経由を使い、拒否試験には Service に選ばれない Pod を使います。
書き込み検証は専用の一時データを使い、確認後にデータと検証用 Pod を削除します。

障害時は新しい公開を戻し、Git revert と ArgoCD 同期で復旧します。
コントローラの fail-open / NRI の制約と緊急切り戻しは [NetworkPolicy の運用](network-policy.md) を参照してください。

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
