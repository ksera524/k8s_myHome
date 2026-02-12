# 外部公開（Cloudflared + Gateway API + DNS-01）の運用手順

このドキュメントは、外部公開の標準構成と、新しい接続先を追加する際の手順をまとめたものです。
外部公開は Cloudflared 経由で Gateway に統一し、TLS は Cloudflare DNS-01（Let’s Encrypt）で発行します。

## 方針の要点

- 外部公開は `*.qroksera.com` を使用
- Cloudflared の origin は `nginx-gateway` に統一
- TLS 証明書は `letsencrypt-cloudflare` の ClusterIssuer を利用
- NodePort は使用しない（Service は ClusterIP）
- RustFS は console のみ外部公開（API は外部公開しない）

## 現在の構成ポイント

- Cloudflare DNS-01 用の ExternalSecret を追加
- ClusterIssuer `letsencrypt-cloudflare` を追加
- 外部公開はワイルドカード証明書を 1 枚だけ `nginx-gateway` に配置
- 各アプリは HTTPRoute のみ追加（証明書は追加しない）
- RustFS Service を NodePort から ClusterIP に変更
- Cloudflared の origin は `nginx-gateway` に統一

## 新しい接続先を追加する手順

### 1. ExternalSecret（Cloudflare API Token）を用意

Pulumi ESC の `dns-01` を使用して、`cert-manager` namespace に Secret を同期します。

- 対象ファイル: `manifests/platform/secrets/external-secrets/external-secret-resources.yaml`
- 既存の `cloudflare-api-token` を再利用する

### 2. ClusterIssuer を確認

外部Issuer が存在することを確認します。

```bash
kubectl get clusterissuer letsencrypt-cloudflare
```

### 3. ワイルドカード Certificate を作成

外部公開は `nginx-gateway` に 1 枚だけ発行します。

- 対象ファイル: `manifests/infrastructure/networking/nginx-gateway-fabric/gateway/wildcard-external-cert.yaml`

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-external
  namespace: nginx-gateway
spec:
  secretName: wildcard-external-tls
  issuerRef:
    name: letsencrypt-cloudflare
    kind: ClusterIssuer
  dnsNames:
    - "*.qroksera.com"
  usages:
    - digital signature
    - key encipherment
    - server auth
```

### 3.5 個別証明書の運用（任意）

アプリ単位の証明書を使う場合のみ ReferenceGrant が必要です。
ワイルドカード運用では **ReferenceGrant 不要** です。

### 4. HTTPRoute を追加

同じく `manifests/apps/<app>/` 配下へ HTTPRoute を追加し、Gateway 経由で公開します。

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <app>-external-redirect
  namespace: <namespace>
spec:
  parentRefs:
    - name: nginx-gateway
      namespace: nginx-gateway
      sectionName: http
  hostnames:
    - <app>.qroksera.com
  rules:
    - filters:
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <app>-external
  namespace: <namespace>
spec:
  parentRefs:
    - name: nginx-gateway
      namespace: nginx-gateway
      sectionName: https
  hostnames:
    - <app>.qroksera.com
  rules:
    - backendRefs:
        - name: <service>
          port: <port>
```

### 5. Application 定義を追加

`manifests/apps/<app>/` の適用は App-of-Apps 配下の Application で管理します。

- 追加先: `manifests/bootstrap/applications/user-apps/`
- 例: `argocd-external-app.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app>-external
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/ksera524/k8s_myHome.git
    targetRevision: HEAD
    path: manifests/apps/<app>
  destination:
    server: https://kubernetes.default.svc
    namespace: <namespace>
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### 6. Cloudflared を設定

origin は Gateway に統一し、TLS 検証は **ON** のままにします。
`rustfs.qroksera.com` も `nginx-gateway` を向け、古い `ingress-nginx` を参照しないようにします。

```yaml
ingress:
  - hostname: <app>.qroksera.com
    service: https://nginx-gateway-nginx.nginx-gateway.svc.cluster.local:443
    originRequest:
      originServerName: <app>.qroksera.com
      httpHostHeader: <app>.qroksera.com
      noTLSVerify: false
  - service: http_status:404
```

**ポイント**
- `Origin Server Name` と `HTTP Host Header` を必ず一致させる
- これが未設定だと TLS 検証が失敗しやすい
 - `nginx-gateway` の証明書が staging のままだと TLS 検証で 502 になる

### 6.1 Cloudflared（credentials.json 方式）で接続先を追加する手順

この手順は **credentials.json 方式**（Managed Tunnel の token ではなくローカル設定優先）を前提とします。

#### 1. Pulumi ESO に credentials.json を登録

- Pulumi ESC の `cloudflared` キーに `credentials.json` の文字列を登録
- ExternalSecret により Secret `cloudflared` の `token` キーに同期される前提

#### 2. config.yml を更新

`manifests/apps/cloudflared/cloudflared-config.yaml` の `config.yml` に追記します。

```yaml
tunnel: <tunnel-id>
credentials-file: /etc/cloudflared/creds/credentials.json
ingress:
  - hostname: <app>.qroksera.com
    service: https://nginx-gateway-nginx.nginx-gateway.svc.cluster.local:443
    originRequest:
      originServerName: <app>.qroksera.com
  - service: http_status:404
```

#### 3. Deployment を更新

`manifests/apps/cloudflared/manifest.yaml` を更新します。

- `--token` を削除
- Secret を volume でマウントし、`token -> credentials.json` に変換
- `credentials-file` を `/etc/cloudflared/creds/credentials.json` に合わせる

#### 4. DNS レコードを CLI で追加

```bash
cloudflared tunnel route dns <tunnel-id> <hostname>
```

例:

```bash
cloudflared tunnel route dns <tunnel-id> rustfs.qroksera.com
```

#### 5. 反映確認

```bash
nslookup <hostname>
kubectl -n cloudflared logs deploy/cloudflared | grep "Updated to new configuration"
curl -k https://<hostname>/
```

#### 6. 注意点

- Managed Tunnel（token 運用）だと Cloudflare 側の設定が優先され、Git管理の ingress が反映されない
- DNS レコードが未登録だと `nslookup` は `No answer` になる

### 7. 反映と確認

```bash
kubectl -n argocd annotate application user-application-definitions \
  argocd.argoproj.io/refresh=hard --overwrite

kubectl get certificate -A
kubectl get gateway -A
kubectl get httproute -A
```

## トラブルシュート

### 証明書が Ready にならない

```bash
kubectl describe certificate <name> -n <namespace>
kubectl get certificaterequest -A | grep qroksera
kubectl get order -A | grep qroksera
kubectl get challenge -A | grep qroksera
```

### Cloudflared で TLS 検証失敗

- `Origin Server Name` と `HTTP Host Header` が一致しているか確認
- `noTLSVerify` は OFF（検証有効）で運用する
 - ワイルドカード証明書が本番Issuerか確認（staging は 502 になる）
