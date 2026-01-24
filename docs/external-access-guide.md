# 外部公開（Cloudflared + Ingress + DNS-01）の運用手順

このドキュメントは、今回の移行作業のまとめと、今後新しい接続先を追加する際の手順書です。
外部公開は Cloudflared 経由で Ingress に統一し、TLS は Cloudflare DNS-01（Let’s Encrypt）で発行します。

## 方針の要点

- 外部公開は `*.qroksera.com` を使用
- Cloudflared の origin は `ingress-nginx` に統一
- TLS 証明書は `letsencrypt-cloudflare` の ClusterIssuer を利用
- NodePort は使用しない（Service は ClusterIP）
- RustFS は console のみ外部公開（API は外部公開しない）

## 今回の作業まとめ

- Cloudflare DNS-01 用の ExternalSecret を追加
- ClusterIssuer `letsencrypt-cloudflare` を追加
- ArgoCD / RustFS の外部用 Certificate + Ingress を追加
- Harbor 外部 Ingress の issuer を外部用に切り替え
- RustFS Service を NodePort から ClusterIP に変更
- Cloudflared の origin を Ingress 経由に統一

## 新しい接続先を追加する手順

### 1. ExternalSecret（Cloudflare API Token）を用意

Pulumi ESC の `dns-01` を使用して、`cert-manager` namespace に Secret を同期します。

- 対象ファイル: `manifests/platform/secrets/external-secrets/externalsecrets.yaml`
- 既存の `cloudflare-api-token` を再利用する

### 2. ClusterIssuer を確認

外部Issuer が存在することを確認します。

```bash
kubectl get clusterissuer letsencrypt-cloudflare
```

### 3. Certificate を作成

アプリごとに `manifests/apps/<app>/` 配下へ証明書を追加します。

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: <app>-external-cert
  namespace: <namespace>
spec:
  secretName: <app>-external-tls
  issuerRef:
    name: letsencrypt-cloudflare
    kind: ClusterIssuer
  dnsNames:
    - <app>.qroksera.com
  usages:
    - digital signature
    - key encipherment
    - server auth
```

### 4. Ingress を追加

同じく `manifests/apps/<app>/` 配下へ Ingress を追加し、TLS secret を指定します。

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <app>-external-ingress
  namespace: <namespace>
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - <app>.qroksera.com
      secretName: <app>-external-tls
  rules:
    - host: <app>.qroksera.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: <service>
                port:
                  number: <port>
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

origin は Ingress に統一し、TLS 検証は **ON** のままにします。

```yaml
ingress:
  - hostname: <app>.qroksera.com
    service: https://ingress-nginx-controller.ingress-nginx.svc.cluster.local:443
    originRequest:
      originServerName: <app>.qroksera.com
      httpHostHeader: <app>.qroksera.com
      noTLSVerify: false
  - service: http_status:404
```

**ポイント**
- `Origin Server Name` と `HTTP Host Header` を必ず一致させる
- これが未設定だと TLS 検証が失敗しやすい

### 7. 反映と確認

```bash
kubectl -n argocd annotate application user-application-definitions \
  argocd.argoproj.io/refresh=hard --overwrite

kubectl get certificate -A
kubectl get ingress -A
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
