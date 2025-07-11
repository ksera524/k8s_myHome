# Phase 5: アプリケーション移行

既存のアプリケーション（factorio除く）をk8sクラスタに移行します。

## 概要

以下のアプリケーションを移行します：

- **CloudFlared**: Cloudflareトンネル機能
- **Slack**: Slackボット
- **RSS**: RSS監視・通知（CronJob）
- **S3S**: Webアプリケーション
- **PEPUP**: Webアプリケーション  
- **HITOMI**: Webアプリケーション

**除外**: factorio（使用していないため）

## 前提条件

Phase 4の基本インフラ構築が完了していることを確認：

```bash
# LoadBalancer IP確認
kubectl -n ingress-nginx get service ingress-nginx-controller

# 基本インフラ確認
kubectl get pods --all-namespaces | grep -E "(metallb|ingress|cert-manager)"
```

## 🚀 実行方法

### Phase 5実行（準備フェーズ）

```bash
# Phase 5 アプリケーション移行準備
./phase5-deploy.sh
```

このスクリプトは以下を実行します：
1. Namespace作成
2. Manifestファイル生成・配置
3. Secret设定テンプレート作成

### 手動設定（必須）

Phase 5スクリプト実行後、以下の手動設定が必要です：

#### 1. Secretの設定

```bash
ssh k8suser@192.168.122.10

# Secret設定ファイルを編集
vi /tmp/secrets-template.yaml

# 以下の値をBase64エンコードして設定
# - CLOUDFLARED_TOKEN: CloudflareトンネルToken
# - SLACK_BOT_TOKEN: SlackボットToken  
# - DATABASE_URL: TiDB接続URL

# Secret適用
kubectl apply -f /tmp/secrets-template.yaml
```

#### 2. アプリケーションデプロイ

```bash
# 全アプリケーションデプロイ
kubectl apply -f /tmp/cloudflared-k8s.yaml
kubectl apply -f /tmp/slack-k8s.yaml  
kubectl apply -f /tmp/rss-k8s.yaml
kubectl apply -f /tmp/s3s-k8s.yaml
kubectl apply -f /tmp/pepup-k8s.yaml
kubectl apply -f /tmp/hitomi-k8s.yaml
```

## アプリケーション詳細

### CloudFlared
- **種類**: Deployment
- **Replicas**: 2
- **機能**: Cloudflareトンネル
- **ポート**: 2000（メトリクス）

### Slack
- **種類**: Deployment + Service + Ingress
- **Replicas**: 1
- **アクセス**: `http://192.168.122.100/slack`
- **ポート**: 3000

### RSS Monitor
- **種類**: CronJob
- **スケジュール**: 毎日8時実行
- **機能**: RSS監視・Slack通知

### S3S
- **種類**: Deployment + Service + Ingress
- **Replicas**: 1
- **アクセス**: `http://192.168.122.100/s3s`
- **ポート**: 8080

### PEPUP
- **種類**: Deployment + Service + Ingress
- **Replicas**: 1
- **アクセス**: `http://192.168.122.100/pepup`
- **ポート**: 8080

### HITOMI
- **種類**: Deployment + Service + Ingress
- **Replicas**: 1
- **アクセス**: `http://192.168.122.100/hitomi`
- **ポート**: 8080

## Secret設定例

### Base64エンコード方法

```bash
# 文字列をBase64エンコード
echo -n "your-secret-value" | base64

# 例：
echo -n "your-cloudflare-token" | base64
echo -n "xoxb-your-slack-token" | base64
echo -n "mysql://user:pass@host:port/db" | base64
```

### Secret YAML例

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudflared
  namespace: cloudflared
type: Opaque
data:
  token: eW91ci1jbG91ZGZsYXJlLXRva2Vu  # your-cloudflare-token

---
apiVersion: v1
kind: Secret
metadata:
  name: slack3
  namespace: sandbox
type: Opaque
data:
  token: eG94Yi15b3VyLXNsYWNrLXRva2Vu  # xoxb-your-slack-token

---
apiVersion: v1
kind: Secret
metadata:
  name: tidb
  namespace: sandbox
type: Opaque
data:
  uri: bXlzcWw6Ly91c2VyOnBhc3NAaG9zdDpwb3J0L2Ri  # mysql://user:pass@host:port/db
```

## デプロイ後の確認

### Pod状態確認

```bash
# 全Pod状態確認
kubectl get pods --all-namespaces

# 各Namespace別確認
kubectl get pods -n cloudflared
kubectl get pods -n sandbox
```

### Service・Ingress確認

```bash
# Service確認
kubectl get service --all-namespaces

# Ingress確認
kubectl get ingress --all-namespaces
```

### アクセステスト

```bash
# LoadBalancer IP確認
LB_IP=$(kubectl -n ingress-nginx get service ingress-nginx-controller -o jsonpath="{.status.loadBalancer.ingress[0].ip}")

# Webアプリケーションアクセステスト
curl http://$LB_IP/slack
curl http://$LB_IP/s3s
curl http://$LB_IP/pepup
curl http://$LB_IP/hitomi

# CloudFlaredメトリクス確認（Port Forward必要）
kubectl -n cloudflared port-forward deployment/cloudflared 2000:2000 &
curl http://localhost:2000/metrics
```

## Ingress設定

各Webアプリケーションには以下のIngressルールが設定されます：

```yaml
# 例：Slack
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: slack
  namespace: sandbox
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /slack
        pathType: Prefix
        backend:
          service:
            name: slack
            port:
              number: 3000
```

## トラブルシューティング

### Pod起動失敗

```bash
# Pod詳細確認
kubectl describe pod <pod-name> -n <namespace>

# Pod ログ確認
kubectl logs <pod-name> -n <namespace>

# Secret確認
kubectl get secret -n <namespace>
kubectl describe secret <secret-name> -n <namespace>
```

### Ingress接続問題

```bash
# Ingress状態確認
kubectl describe ingress <ingress-name> -n <namespace>

# NGINX Ingress Controller ログ確認
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# LoadBalancer確認
kubectl -n ingress-nginx get service ingress-nginx-controller
```

### Image Pull失敗

```bash
# Harbor設定確認（必要に応じて）
kubectl get secret harbor -n <namespace>

# Image Pull Secret設定
kubectl create secret docker-registry harbor \
  --docker-server=192.168.122.100:30003 \
  --docker-username=<username> \
  --docker-password=<password> \
  -n <namespace>
```

## Harbor設定（必要に応じて）

現在のイメージレジストリが`192.168.10.11:30003`から`192.168.122.100:30003`に変更されています。Harbor設定の更新が必要な場合があります。

### Harbor移行手順

```bash
# 1. Harbor Helmチャート（別途設定）
# 2. 既存イメージの移行
# 3. imagePullSecretsの更新
```

## 期待される結果

### 正常なデプロイ完了時

```bash
$ kubectl get pods --all-namespaces | grep -E "(cloudflared|slack|s3s|pepup|hitomi)"
cloudflared      cloudflared-xxx-xxx                     1/1     Running   0          5m
sandbox          slack-xxx-xxx                           1/1     Running   0          5m
sandbox          s3s-xxx-xxx                             1/1     Running   0          5m
sandbox          pepup-xxx-xxx                           1/1     Running   0          5m
sandbox          hitomi-xxx-xxx                          1/1     Running   0          5m

$ kubectl get ingress --all-namespaces
NAMESPACE   NAME     CLASS   HOSTS         ADDRESS           PORTS   AGE
sandbox     slack    nginx   slack.local   192.168.122.100   80      5m
sandbox     s3s      nginx   *             192.168.122.100   80      5m
sandbox     pepup    nginx   *             192.168.122.100   80      5m
sandbox     hitomi   nginx   *             192.168.122.100   80      5m
```

### アクセステスト結果

```bash
$ curl http://192.168.122.100/slack
# Slackアプリケーションのレスポンス

$ curl http://192.168.122.100/s3s  
# S3Sアプリケーションのレスポンス
```

## 次のステップ

Phase 5完了後：

1. **監視設定**: Prometheus, Grafana
2. **ログ管理**: ELK Stack または Loki
3. **バックアップ**: Velero
4. **CI/CD**: GitHub Actions Self-hosted Runner
5. **SSL/TLS**: Let's Encrypt証明書設定