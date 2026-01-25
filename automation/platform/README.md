# Phase 4: 基本インフラ構築

Phase 3で構築されたk8sクラスタに対して、基本的なインフラストラクチャコンポーネントを自動インストールします。

## 概要

以下のコンポーネントを自動構築します：

- **MetalLB**: LoadBalancer機能（ベアメタル環境用）
- **NGINX Gateway Fabric**: HTTP/HTTPSルーティング
- **cert-manager**: TLS証明書自動管理
- **StorageClass**: 永続ストレージ設定
- **ArgoCD**: GitOps継続的デプロイメント
- **Harbor**: コンテナレジストリ・セキュリティスキャン
- **Actions Runner Controller**: GitHub Actions自動実行環境

## 前提条件

Phase 3のk8sクラスタ構築が完了していることを確認：

```bash
# k8sクラスタ状態確認
ssh k8suser@192.168.122.10 'kubectl get nodes'

# 3台のNodeがReady状態であることを確認
NAME                STATUS   ROLES           AGE   VERSION
k8s-control-plane   Ready    control-plane   1h    v1.xx.x
k8s-worker1         Ready    <none>          1h    v1.xx.x
k8s-worker2         Ready    <none>          1h    v1.xx.x
```

## 🚀 実行方法

### ワンコマンド実行（推奨）

```bash
# Phase 4 基本インフラ自動構築 + Harbor証明書修正 + イメージプルシークレット作成
./phase4-deploy.sh

# または、Harbor関連の設定のみ実行
./harbor-cert-fix.sh

# または、イメージプルシークレットのみ作成
./create-harbor-secrets.sh
```

### 手動実行

```bash
# 1. MetalLB インストール
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

# 2. Gateway API CRD + NGINX Gateway Fabric インストール
kubectl kustomize "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v2.3.0" | kubectl apply -f -
helm install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric --create-namespace -n nginx-gateway
kubectl apply -f manifests/infrastructure/networking/nginx-gateway-fabric/gateway/gateway.yaml

# 3. cert-manager インストール
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# 4. ArgoCD インストール
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 5. Harbor インストール (ArgoCD経由)
helm repo add harbor https://helm.goharbor.io
helm install harbor harbor/harbor --namespace harbor --create-namespace

# 6. GitHub Actions Runner Controller (ARC) は make all で自動デプロイ
# setup-arc.sh により自動的に公式 GitHub ARC がデプロイされます
```

## 構築内容

### Phase 4.1: MetalLB（LoadBalancer）
- IPアドレスプール: `192.168.122.100-192.168.122.150`
- L2Advertisement設定
- LoadBalancer Serviceの自動IP割り当て

### Phase 4.2: NGINX Gateway Fabric
- Gateway API によるHTTP/HTTPSルーティング
- Gateway Service経由でのアクセス
- TLS終端機能

### Phase 4.3: cert-manager
- TLS証明書の自動取得・更新
- Self-signed ClusterIssuer（開発用）
- Let's Encrypt対応（本番用）

### Phase 4.4: StorageClass
- Local StorageClass設定
- 永続ボリューム管理

### Phase 4.5: ArgoCD
- GitOps継続的デプロイメント
- アプリケーション自動同期
- Webベース管理UI

### Phase 4.6: Harbor
- プライベートコンテナレジストリ
- 脆弱性スキャン（Trivy統合）
- イメージ署名・検証
- Webベース管理UI

### Phase 4.7: Actions Runner Controller (ARC)
- GitHub Actions自動実行環境
- セルフホスト型ランナー
- 自動スケーリング機能

## 構築後の確認

### インフラコンポーネント状態確認

```bash
# 全コンポーネント状態
kubectl get pods --all-namespaces | grep -E "(metallb|nginx-gateway|cert-manager|argocd|harbor|actions-runner)"

# MetalLB状態
kubectl get pods -n metallb-system

# NGINX Gateway Fabric状態
kubectl get pods -n nginx-gateway
kubectl -n nginx-gateway get service nginx-gateway-nginx

# cert-manager状態
kubectl get pods -n cert-manager
kubectl get clusterissuer

# ArgoCD状態
kubectl get pods -n argocd
kubectl -n argocd get service argocd-server

# Harbor状態
kubectl get pods -n harbor
kubectl -n harbor get service harbor-core

# GitHub Actions Runner Controller (ARC) 状態
kubectl get pods -n arc-systems
kubectl get autoscalingrunnersets -n arc-systems
```

### LoadBalancer IP確認

```bash
# LoadBalancer Service IP確認
kubectl -n nginx-gateway get service nginx-gateway-nginx

NAME                 TYPE           CLUSTER-IP      EXTERNAL-IP       PORT(S)
nginx-gateway-nginx  LoadBalancer   10.96.X.X       192.168.122.100   80:XXXXX/TCP,443:XXXXX/TCP
```

## 期待される結果

### 正常な構築完了時

```bash
=== インフラコンポーネント状態 ===
MetalLB: 3 Pod(s) Running
NGINX Gateway Fabric: 2 Pod(s) Running
cert-manager: 3 Pod(s) Running
ArgoCD: 7 Pod(s) Running
Harbor: 8 Pod(s) Running
Actions Runner Controller: 1 Pod(s) Running
LoadBalancer IP: 192.168.122.100
```

## 使用例

### HTTPRoute設定例

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: example-route
spec:
  parentRefs:
    - name: nginx-gateway
      namespace: nginx-gateway
      sectionName: https
  hostnames:
    - example.local
  rules:
    - backendRefs:
        - name: example-service
          port: 80
```

### TLS証明書設定例

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-tls
spec:
  secretName: example-tls-secret
  issuerRef:
    name: selfsigned-cluster-issuer
    kind: ClusterIssuer
  dnsNames:
  - example.local
```

### ArgoCD HTTPRoute設定例

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd-server
  namespace: argocd
spec:
  parentRefs:
    - name: nginx-gateway
      namespace: nginx-gateway
      sectionName: https
  hostnames:
    - argocd.local
  rules:
    - backendRefs:
        - name: argocd-server
          port: 80
```

### Harbor HTTPRoute設定例

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: harbor
  namespace: harbor
spec:
  parentRefs:
    - name: nginx-gateway
      namespace: nginx-gateway
      sectionName: https
  hostnames:
    - harbor.local
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: harbor-core
          port: 80
---
apiVersion: gateway.nginx.org/v1alpha1
kind: ClientSettingsPolicy
metadata:
  name: harbor-client-settings
  namespace: harbor
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: harbor
  body:
    maxSize: "0"
```

### GitHub Actions Workflow例

```yaml
name: Build and Push to Harbor
on:
  push:
    branches: [ main ]

jobs:
  build:
    runs-on: [self-hosted, linux, k8s]
    steps:
    - uses: actions/checkout@v4
    
    - name: Build Docker image
      run: |
        docker build -t harbor.local/library/myapp:${{ github.sha }} .
    
    - name: Push to Harbor
      run: |
        echo "${{ secrets.HARBOR_PASSWORD }}" | docker login harbor.local -u admin --password-stdin
        docker push harbor.local/library/myapp:${{ github.sha }}
```

## 次のステップ

Phase 4完了後は、Phase 5（アプリケーション追加/展開）に進みます：

1. **アプリケーション追加**: factorio, slack, cloudflared等
2. **HTTPRoute設定**: HTTP/HTTPSアクセス設定
3. **TLS証明書**: 本番用証明書設定
4. **監視・ログ**: Prometheus, Grafana等

## トラブルシューティング

### MetalLB問題

```bash
# MetalLB Pod状態確認
kubectl get pods -n metallb-system

# MetalLB設定確認
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
```

### NGINX Gateway Fabric問題

```bash
# Gateway Fabric状態確認
kubectl get pods -n nginx-gateway

# LoadBalancer Service確認
kubectl -n nginx-gateway get service nginx-gateway-nginx

# Gateway Fabric ログ確認
kubectl -n nginx-gateway logs deployment/ngf-nginx-gateway-fabric
kubectl -n nginx-gateway logs deployment/nginx-gateway-nginx
```

### cert-manager問題

```bash
# cert-manager Pod状態確認
kubectl get pods -n cert-manager

# ClusterIssuer状態確認
kubectl get clusterissuer

# Certificate状態確認
kubectl get certificate
kubectl describe certificate [certificate-name]
```

### ArgoCD問題

```bash
# ArgoCD Pod状態確認
kubectl get pods -n argocd

# ArgoCD管理者パスワード取得
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# ArgoCD Service確認
kubectl -n argocd get service argocd-server

# ArgoCD Server ログ確認
kubectl -n argocd logs -l app.kubernetes.io/component=server
```

### Harbor問題

```bash
# Harbor Pod状態確認
kubectl get pods -n harbor

# Harbor Core サービス確認
kubectl -n harbor get service harbor-core

# Harbor管理者パスワード確認
kubectl -n harbor get secret harbor-core -o jsonpath="{.data.HARBOR_ADMIN_PASSWORD}" | base64 -d

# Harbor Core ログ確認
kubectl -n harbor logs -l app=harbor,component=core

# Harbor イメージプルシークレット確認
kubectl get secrets -n sandbox | grep harbor-http
kubectl get secrets -n default | grep harbor-http

# Harbor イメージプル権限テスト
kubectl run test-harbor --image=192.168.122.100/sandbox/slack.rs:latest --dry-run=client -o yaml | \
sed '/^metadata:/a\
  namespace: sandbox' | kubectl apply -f -
```

### Actions Runner Controller問題

```bash
# ARC Pod状態確認
kubectl get pods -n arc-systems

# AutoScaling Runner Sets状態確認
kubectl get autoscalingrunnersets -n arc-systems

# Runner Pod状態確認
kubectl get pods -n arc-systems | grep runner

# ARC Controller ログ確認
kubectl -n arc-systems logs -l app.kubernetes.io/name=gha-rs-controller

# GitHub Token Secret確認
kubectl -n arc-systems get secret github-multi-repo-secret
```

### LoadBalancer IP取得失敗

```bash
# MetalLB設定確認
kubectl -n metallb-system get ipaddresspool
kubectl -n metallb-system get l2advertisement

# ネットワーク設定確認
ip route
```

## 高度な設定

### Let's Encrypt証明書（本番用）

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```

### カスタムStorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
parameters:
  type: ssd
```
