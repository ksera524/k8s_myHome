# アプリケーション管理

## 概要

k8s_myHomeで管理されているアプリケーションの詳細と、新しいアプリケーションの追加方法について説明します。

## デプロイ済みアプリケーション

### 1. Slack Bot

**概要**: Slackとの統合ボットアプリケーション

| 項目 | 内容 |
|------|------|
| **Namespace** | sandbox |
| **イメージ** | harbor.qroksera.com/sandbox/slack.rs:latest |
| **サービス** | NodePort (32001) |
| **Secret** | slack（SLACK_BOT_TOKEN） |
| **ソースコード** | manifests/apps/slack/ |

**主な設定**:
```yaml
# Deployment
replicas: 1
resources:
  limits:
    memory: "128Mi"
    cpu: "500m"
```

### 2. Cloudflared

**概要**: Cloudflare Tunnelクライアント

| 項目 | 内容 |
|------|------|
| **Namespace** | cloudflared |
| **イメージ** | cloudflare/cloudflared:latest |
| **タイプ** | Deployment |
| **Secret** | cloudflared |
| **ソースコード** | manifests/apps/cloudflared/ |

**用途**:
- 外部からの安全なアクセス
- Cloudflare Zero Trust統合

### 3. RSS Reader

**概要**: RSSフィード管理アプリケーション

| 項目 | 内容 |
|------|------|
| **Namespace** | sandbox |
| **タイプ** | CronJob |
| **スケジュール** | 毎日実行 |
| **ストレージ** | なし |
| **ソースコード** | manifests/apps/rss/ |

### 4. Hitomi Downloader

**概要**: コンテンツダウンローダー

| 項目 | 内容 |
|------|------|
| **Namespace** | sandbox |
| **タイプ** | CronJob |
| **スケジュール** | 定期実行 |
| **ストレージ** | なし |
| **ソースコード** | manifests/apps/hitomi/ |

### 5. Pepup

**概要**: カスタムアプリケーション

| 項目 | 内容 |
|------|------|
| **Namespace** | sandbox |
| **タイプ** | CronJob |
| **設定** | Secret使用 |
| **ソースコード** | manifests/apps/pepup/ |

## 参考: 監視スタック（未デプロイ）

Grafana Cloud 連携用の設定値は `manifests/monitoring/` と
`manifests/config/secrets/` に用意していますが、App-of-Appsには未接続です。
必要になったタイミングで導入してください。

## 新規アプリケーションの追加

### 1. ディレクトリ構造の作成

```bash
# アプリケーション用ディレクトリ作成
mkdir -p manifests/apps/myapp
cd manifests/apps/myapp
```

### 2. Kubernetesマニフェスト作成

#### deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: sandbox
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      imagePullSecrets:
      - name: harbor-registry-secret
      containers:
      - name: myapp
        image: harbor.qroksera.com/sandbox/myapp:latest
        ports:
        - containerPort: 8080
        env:
        - name: API_KEY
          valueFrom:
            secretKeyRef:
              name: myapp-secret
              key: api-key
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "128Mi"
            cpu: "500m"
```

#### service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: sandbox
spec:
  selector:
    app: myapp
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP
```

#### ingress.yaml

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  namespace: sandbox
  annotations:
    cert-manager.io/cluster-issuer: selfsigned-issuer
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - myapp.local
    secretName: myapp-tls
  rules:
  - host: myapp.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 80
```

### 3. External Secret設定

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: myapp-secret
  namespace: sandbox
spec:
  refreshInterval: 20s
  secretStoreRef:
    name: pulumi-esc-store
    kind: ClusterSecretStore
  target:
    name: myapp-secret
    creationPolicy: Owner
  data:
  - secretKey: api-key
    remoteRef:
      key: myapp-api-key
```

### 4. ArgoCD Application定義

```yaml
# manifests/bootstrap/applications/user-apps/myapp-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "12"
spec:
  project: default
  source:
    repoURL: https://github.com/ksera524/k8s_myHome.git
    targetRevision: HEAD
    path: manifests/apps/myapp
  destination:
    server: https://kubernetes.default.svc
    namespace: sandbox
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

### 5. イメージのビルドとプッシュ

```bash
# Dockerfile作成
cat > Dockerfile <<EOF
FROM alpine:latest
COPY app /app
ENTRYPOINT ["/app"]
EOF

# ビルド
docker build -t myapp:latest .

# タグ付け
docker tag myapp:latest harbor.qroksera.com/sandbox/myapp:latest

# Harbor へプッシュ
docker push harbor.qroksera.com/sandbox/myapp:latest
```

### 6. デプロイとテスト

```bash
# Git にコミット
git add manifests/apps/myapp/
git commit -m "Add myapp application"
git push

# ArgoCD同期待ち（自動）
# または手動同期
kubectl patch application myapp -n argocd \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# デプロイ確認
kubectl get pods -n sandbox | grep myapp
kubectl logs -n sandbox deployment/myapp
```

## CronJobアプリケーション

### CronJob定義例

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: scheduled-task
  namespace: sandbox
spec:
  schedule: "0 2 * * *"  # 毎日午前2時
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: task
            image: harbor.qroksera.com/sandbox/task:latest
            command: ["/bin/sh", "-c"]
            args: ["echo 'Task executed'"]
```

### スケジュール設定

| 設定 | 説明 | 例 |
|------|------|-----|
| `*/5 * * * *` | 5分ごと | 頻繁なタスク |
| `0 * * * *` | 毎時0分 | 時間単位のタスク |
| `0 2 * * *` | 毎日午前2時 | 日次バッチ |
| `0 0 * * 0` | 毎週日曜日 | 週次タスク |
| `0 0 1 * *` | 毎月1日 | 月次タスク |

## アプリケーション管理コマンド

### デプロイ状態確認

```bash
# Application一覧
kubectl get applications -n argocd

# 特定アプリケーションの詳細
kubectl describe application <app-name> -n argocd

# Pod状態
kubectl get pods -n <namespace>

# ログ確認
kubectl logs -n <namespace> <pod-name>
```

### スケーリング

```bash
# レプリカ数変更
kubectl scale deployment <deployment-name> -n <namespace> --replicas=3

# HPA設定
kubectl autoscale deployment <deployment-name> -n <namespace> \
  --cpu-percent=50 --min=1 --max=10
```

### アップデート

```bash
# イメージ更新
kubectl set image deployment/<deployment-name> \
  <container-name>=harbor.qroksera.com/sandbox/<image>:new-tag \
  -n <namespace>

# ローリングアップデート状態
kubectl rollout status deployment/<deployment-name> -n <namespace>

# ロールバック
kubectl rollout undo deployment/<deployment-name> -n <namespace>
```

## Harbor レジストリ管理

### プロジェクト作成

```bash
# Harbor UI経由
# Projects > New Project
# Name: myproject
# Access Level: Private
```

### イメージ管理

```bash
# イメージ一覧
curl -X GET "https://harbor.qroksera.com/api/v2.0/projects/sandbox/repositories" \
  -u admin:Harbor12345

# イメージタグ一覧
curl -X GET "https://harbor.qroksera.com/api/v2.0/projects/sandbox/repositories/myapp/artifacts" \
  -u admin:Harbor12345

# イメージ削除
curl -X DELETE "https://harbor.qroksera.com/api/v2.0/projects/sandbox/repositories/myapp" \
  -u admin:Harbor12345
```

### レジストリSecret管理

```bash
# Secret作成
kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=harbor.qroksera.com \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --docker-email=admin@example.com \
  -n <namespace>

# または External Secrets経由（推奨）
```

## ベストプラクティス

### 1. リソース管理

```yaml
resources:
  requests:  # 最小保証リソース
    memory: "64Mi"
    cpu: "250m"
  limits:    # 最大使用可能リソース
    memory: "128Mi"
    cpu: "500m"
```

### 2. ヘルスチェック

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

### 3. ConfigMapとSecret分離

```yaml
# 設定はConfigMap
configMapRef:
  name: app-config

# 機密情報はSecret
secretRef:
  name: app-secret
```

### 4. ラベル管理

```yaml
labels:
  app: myapp
  version: v1.0.0
  environment: production
  team: platform
```

### 5. ネームスペース分離

- `sandbox`: 開発・テスト用
- `production`: 本番用
- `monitoring`: 監視ツール
- `infrastructure`: インフラコンポーネント

## トラブルシューティング

### Pod が起動しない

```bash
# イベント確認
kubectl get events -n <namespace>

# Pod詳細
kubectl describe pod <pod-name> -n <namespace>

# イメージプル確認
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.status.containerStatuses[0].state}'
```

### Secret が見つからない

```bash
# Secret一覧
kubectl get secrets -n <namespace>

# ExternalSecret状態
kubectl get externalsecret -n <namespace>
kubectl describe externalsecret <name> -n <namespace>
```

### Service に接続できない

```bash
# Service確認
kubectl get svc -n <namespace>

# Endpoint確認
kubectl get endpoints -n <namespace>

# DNS解決テスト
kubectl run -it --rm debug --image=alpine --restart=Never -- nslookup <service-name>.<namespace>
```

## まとめ

k8s_myHomeのアプリケーション管理は、GitOpsパターンに基づいて完全に自動化されています。新しいアプリケーションの追加も、標準的なKubernetesマニフェストを作成してGitにプッシュするだけで、ArgoCDが自動的にデプロイを実行します。
