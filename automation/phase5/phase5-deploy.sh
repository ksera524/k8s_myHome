#!/bin/bash

# Phase 5: アプリケーション移行自動化スクリプト
# 既存アプリケーション（factorio除く）をk8sクラスタに移行

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

print_status "=== Phase 5: アプリケーション移行開始 ==="

# 0. 前提条件確認
print_status "前提条件を確認中..."

# k8sクラスタ・インフラ確認
if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
    print_error "k8sクラスタに接続できません"
    exit 1
fi

# LoadBalancer確認
LB_IP=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl -n ingress-nginx get service ingress-nginx-controller -o jsonpath="{.status.loadBalancer.ingress[0].ip}"' 2>/dev/null || echo "")
if [[ -z "$LB_IP" ]]; then
    print_error "LoadBalancer IPが取得できません。Phase 4を先に実行してください"
    exit 1
fi

print_status "✓ k8sクラスタ・インフラ確認OK (LoadBalancer: $LB_IP)"

# 1. Namespace作成
print_status "=== Phase 5.1: Namespace作成 ==="

ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
# 必要なNamespace作成
kubectl create namespace cloudflared --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace sandbox --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Namespace作成完了"
EOF

print_status "✓ Namespace作成完了"

# 2. Secret管理の移行
print_status "=== Phase 5.2: Secret管理設定 ==="
print_debug "既存のSecretを新しいk8sクラスタ用に設定します"

# Secret設定用のテンプレート作成
cat > /tmp/secrets-template.yaml << 'EOF'
# CloudFlared Secret (要手動設定)
apiVersion: v1
kind: Secret
metadata:
  name: cloudflared
  namespace: cloudflared
type: Opaque
data:
  token: <CLOUDFLARED_TOKEN_BASE64>

---
# Slack Secret (要手動設定)
apiVersion: v1
kind: Secret
metadata:
  name: slack3
  namespace: sandbox
type: Opaque
data:
  token: <SLACK_BOT_TOKEN_BASE64>

---
# TiDB Secret (要手動設定)
apiVersion: v1
kind: Secret
metadata:
  name: tidb
  namespace: sandbox
type: Opaque
data:
  uri: <DATABASE_URL_BASE64>
EOF

print_warning "Secret設定が必要です: /tmp/secrets-template.yaml を参照してください"

# 3. CloudFlared アプリケーション移行
print_status "=== Phase 5.3: CloudFlared アプリケーション移行 ==="

# CloudFlared manifest修正版作成
cat > /tmp/cloudflared-k8s.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: cloudflared
  name: cloudflared
  namespace: cloudflared
spec:
  replicas: 2
  selector:
    matchLabels:
      pod: cloudflared
  template:
    metadata:
      labels:
        pod: cloudflared
    spec:
      containers:
      - name: cloudflared
        image: cloudflare/cloudflared:latest
        command:
        - cloudflared
        - tunnel
        - --metrics
        - 0.0.0.0:2000
        - run
        - --token
        - $(CLOUDFLARED_TOKEN)
        env:
        - name: CLOUDFLARED_TOKEN
          valueFrom:
            secretKeyRef:
              name: cloudflared
              key: token
        livenessProbe:
          httpGet:
            path: /ready
            port: 2000
          failureThreshold: 1
          initialDelaySeconds: 10
          periodSeconds: 10
          successThreshold: 1
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
EOF

print_debug "CloudFlared manifest準備完了"

# 4. Slack アプリケーション移行
print_status "=== Phase 5.4: Slack アプリケーション移行 ==="

# Slack manifest修正版作成（Harbor設定を更新）
cat > /tmp/slack-k8s.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: slack
  namespace: sandbox
  labels:
    app: slack
spec:
  replicas: 1
  selector:
    matchLabels:
      pod: slack
  template:
    metadata:
      labels:
        pod: slack
    spec:
      containers:
      - name: slack
        image: 192.168.122.100:30003/sandbox/slack.rs:latest
        env:
        - name: SLACK_BOT_TOKEN
          valueFrom:
            secretKeyRef:
              name: slack3
              key: token
        ports:
        - containerPort: 3000
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"

---
apiVersion: v1
kind: Service
metadata:
  name: slack
  namespace: sandbox
spec:
  selector:
    pod: slack
  ports:
    - protocol: TCP
      port: 3000
      targetPort: 3000

---
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
  - host: slack.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: slack
            port:
              number: 3000
  - http:
      paths:
      - path: /slack
        pathType: Prefix
        backend:
          service:
            name: slack
            port:
              number: 3000
EOF

print_debug "Slack manifest準備完了（Ingress付き）"

# 5. RSS アプリケーション移行
print_status "=== Phase 5.5: RSS アプリケーション移行 ==="

cat > /tmp/rss-k8s.yaml << 'EOF'
apiVersion: batch/v1
kind: CronJob
metadata:
  name: rss-monitor-cronjob
  namespace: sandbox
spec:
  schedule: "0 8 * * *"
  concurrencyPolicy: "Forbid"
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        metadata:
          labels:
            app: rss-monitor
        spec:
          containers:
            - name: rss-monitor
              image: 192.168.122.100:30003/sandbox/rss:latest
              imagePullPolicy: Always
              env:
                - name: TOKEN
                  valueFrom:
                    secretKeyRef:
                      name: slack3
                      key: token
                - name: DATABASE_URL
                  valueFrom:
                    secretKeyRef:
                      name: tidb
                      key: uri
              resources:
                requests:
                  memory: "128Mi"
                  cpu: "100m"
                limits:
                  memory: "256Mi"
                  cpu: "200m"
          restartPolicy: OnFailure
EOF

print_debug "RSS CronJob manifest準備完了"

# 6. その他アプリケーション移行
print_status "=== Phase 5.6: その他アプリケーション移行 ==="

# S3S
cat > /tmp/s3s-k8s.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: s3s
  namespace: sandbox
  labels:
    app: s3s
spec:
  replicas: 1
  selector:
    matchLabels:
      pod: s3s
  template:
    metadata:
      labels:
        pod: s3s
    spec:
      containers:
      - name: s3s
        image: 192.168.122.100:30003/sandbox/s3s:latest
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"

---
apiVersion: v1
kind: Service
metadata:
  name: s3s
  namespace: sandbox
spec:
  selector:
    pod: s3s
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080

---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: s3s
  namespace: sandbox
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /s3s
        pathType: Prefix
        backend:
          service:
            name: s3s
            port:
              number: 8080
EOF

# PEPUP
cat > /tmp/pepup-k8s.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pepup
  namespace: sandbox
  labels:
    app: pepup
spec:
  replicas: 1
  selector:
    matchLabels:
      pod: pepup
  template:
    metadata:
      labels:
        pod: pepup
    spec:
      containers:
      - name: pepup
        image: 192.168.122.100:30003/sandbox/pepup:latest
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"

---
apiVersion: v1
kind: Service
metadata:
  name: pepup
  namespace: sandbox
spec:
  selector:
    pod: pepup
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080

---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pepup
  namespace: sandbox
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /pepup
        pathType: Prefix
        backend:
          service:
            name: pepup
            port:
              number: 8080
EOF

# HITOMI
cat > /tmp/hitomi-k8s.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hitomi
  namespace: sandbox
  labels:
    app: hitomi
spec:
  replicas: 1
  selector:
    matchLabels:
      pod: hitomi
  template:
    metadata:
      labels:
        pod: hitomi
    spec:
      containers:
      - name: hitomi
        image: 192.168.122.100:30003/sandbox/hitomi:latest
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"

---
apiVersion: v1
kind: Service
metadata:
  name: hitomi
  namespace: sandbox
spec:
  selector:
    pod: hitomi
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080

---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hitomi
  namespace: sandbox
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /hitomi
        pathType: Prefix
        backend:
          service:
            name: hitomi
            port:
              number: 8080
EOF

print_debug "全アプリケーション manifest準備完了"

# 7. Manifestファイルの配置
print_status "=== Phase 5.7: Manifestファイル配置 ==="

# k8sクラスタにmanifestファイルを転送
scp -o StrictHostKeyChecking=no /tmp/cloudflared-k8s.yaml k8suser@192.168.122.10:/tmp/
scp -o StrictHostKeyChecking=no /tmp/slack-k8s.yaml k8suser@192.168.122.10:/tmp/
scp -o StrictHostKeyChecking=no /tmp/rss-k8s.yaml k8suser@192.168.122.10:/tmp/
scp -o StrictHostKeyChecking=no /tmp/s3s-k8s.yaml k8suser@192.168.122.10:/tmp/
scp -o StrictHostKeyChecking=no /tmp/pepup-k8s.yaml k8suser@192.168.122.10:/tmp/
scp -o StrictHostKeyChecking=no /tmp/hitomi-k8s.yaml k8suser@192.168.122.10:/tmp/
scp -o StrictHostKeyChecking=no /tmp/secrets-template.yaml k8suser@192.168.122.10:/tmp/

print_status "✓ Manifestファイル配置完了"

# 8. デプロイ手順案内
print_status "=== Phase 5完了: 手動設定が必要 ==="

echo ""
echo "=== 次に実行する手順 ==="
echo ""
echo "1. Secretの設定（必須）:"
echo "   ssh k8suser@192.168.122.10"
echo "   # /tmp/secrets-template.yaml を編集してSecret値を設定"
echo "   kubectl apply -f /tmp/secrets-template.yaml"
echo ""
echo "2. アプリケーションのデプロイ:"
echo "   kubectl apply -f /tmp/cloudflared-k8s.yaml"
echo "   kubectl apply -f /tmp/slack-k8s.yaml"
echo "   kubectl apply -f /tmp/rss-k8s.yaml"
echo "   kubectl apply -f /tmp/s3s-k8s.yaml"
echo "   kubectl apply -f /tmp/pepup-k8s.yaml"
echo "   kubectl apply -f /tmp/hitomi-k8s.yaml"
echo ""
echo "3. デプロイ結果確認:"
echo "   kubectl get pods --all-namespaces"
echo "   kubectl get ingress --all-namespaces"
echo ""
echo "4. アクセステスト:"
echo "   curl http://$LB_IP/slack"
echo "   curl http://$LB_IP/s3s"
echo "   curl http://$LB_IP/pepup"
echo "   curl http://$LB_IP/hitomi"
echo ""

# 9. 設定情報保存
cat > phase5-info.txt << EOF
=== Phase 5 アプリケーション移行準備完了 ===

移行対象アプリケーション:
- CloudFlared: tunnel機能
- Slack: Slackボット
- RSS: 定期実行CronJob
- S3S: Webアプリケーション
- PEPUP: Webアプリケーション  
- HITOMI: Webアプリケーション

アクセス情報（デプロイ後）:
- LoadBalancer IP: $LB_IP
- Slack: http://$LB_IP/slack
- S3S: http://$LB_IP/s3s
- PEPUP: http://$LB_IP/pepup
- HITOMI: http://$LB_IP/hitomi

必要な手動作業:
1. Secret設定（CloudFlared Token, Slack Token, Database URL）
2. アプリケーションデプロイ
3. Harbor設定（必要に応じて）

Manifestファイル場所:
- Control Plane: /tmp/*-k8s.yaml
- Secret Template: /tmp/secrets-template.yaml
EOF

print_status "Phase 5 アプリケーション移行準備が完了しました！"
print_debug "詳細情報: phase5-info.txt"