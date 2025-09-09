#!/bin/bash

# Grafana k8s-monitoring デプロイスクリプト
# External Secrets経由でGrafana Cloud認証情報を取得してデプロイ

set -euo pipefail

# 色設定
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_status() { echo -e "${GREEN}$1${NC}"; }
log_error() { echo -e "${RED}$1${NC}"; }
log_warning() { echo -e "${YELLOW}$1${NC}"; }

# IPアドレス設定
CONTROL_PLANE_IP="${K8S_CONTROL_PLANE_IP:-192.168.122.10}"

log_status "=== Grafana k8s-monitoring デプロイ開始 ==="

# 前提条件確認
log_status "前提条件を確認中..."

# k8sクラスタ接続確認
if ! ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=10 k8suser@${CONTROL_PLANE_IP} 'kubectl get nodes' >/dev/null 2>&1; then
    log_error "k8sクラスタに接続できません"
    exit 1
fi

# External Secrets Operator確認
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << 'EOF'
echo "External Secrets Operator確認中..."
if ! kubectl get deployment -n external-secrets-system external-secrets-operator >/dev/null 2>&1; then
    echo "エラー: External Secrets Operatorがインストールされていません"
    exit 1
fi

# ClusterSecretStore確認
if ! kubectl get clustersecretstore pulumi-esc-store >/dev/null 2>&1; then
    echo "エラー: ClusterSecretStore pulumi-esc-storeが存在しません"
    exit 1
fi

echo "✓ External Secrets Operator準備完了"
EOF

# External Secret マニフェストをコピー
log_status "External Secret マニフェストを適用中..."
scp -o StrictHostKeyChecking=no ../../manifests/config/secrets/grafana-monitoring-externalsecret.yaml k8suser@${CONTROL_PLANE_IP}:/tmp/

# External Secret適用とSecret作成待機
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << 'EOF'
# monitoring namespace作成
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# External Secret適用
kubectl apply -f /tmp/grafana-monitoring-externalsecret.yaml

# Secret作成待機
echo "Grafana Cloud認証情報の同期待機中..."
for i in {1..30}; do
    if kubectl get secret grafana-cloud-monitoring -n monitoring >/dev/null 2>&1; then
        echo "✓ Grafana Cloud認証情報取得完了"
        break
    fi
    echo "Secret同期待機中... ($i/30)"
    sleep 5
done

# Secret存在確認
if ! kubectl get secret grafana-cloud-monitoring -n monitoring >/dev/null 2>&1; then
    echo "エラー: Grafana Cloud認証情報を取得できませんでした"
    echo "Pulumi ESCに 'grafana' キーが設定されているか確認してください"
    exit 1
fi

# 認証情報取得（API Tokenのみ）
API_TOKEN=$(kubectl get secret grafana-cloud-monitoring -n monitoring -o jsonpath='{.data.api-token}' | base64 -d)

if [[ -z "$API_TOKEN" ]]; then
    echo "エラー: API Tokenを取得できませんでした"
    exit 1
fi

# ユーザー名は固定値
METRICS_USERNAME="2666273"
LOGS_USERNAME="1328813"
OTLP_USERNAME="1371019"

echo "✓ 認証情報取得完了"
EOF

# Grafana k8s-monitoring values ファイル作成
log_status "Grafana k8s-monitoring values ファイル作成中..."
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << 'EOF'
# 認証情報取得（API Tokenのみ）
API_TOKEN=$(kubectl get secret grafana-cloud-monitoring -n monitoring -o jsonpath='{.data.api-token}' | base64 -d)

# ユーザー名は固定値
METRICS_USERNAME="2666273"
LOGS_USERNAME="1328813"
OTLP_USERNAME="1371019"

# Values ファイル作成
cat > /tmp/grafana-k8s-monitoring-values.yaml << VALUES_EOF
cluster:
  name: k8s-myhome
destinations:
  - name: grafana-cloud-metrics
    type: prometheus
    url: https://prometheus-prod-49-prod-ap-northeast-0.grafana.net/api/prom/push
    auth:
      type: basic
      username: "${METRICS_USERNAME}"
      password: ${API_TOKEN}
  - name: grafana-cloud-logs
    type: loki
    url: https://logs-prod-030.grafana.net/loki/api/v1/push
    auth:
      type: basic
      username: "${LOGS_USERNAME}"
      password: ${API_TOKEN}
  - name: gc-otlp-endpoint
    type: otlp
    url: https://otlp-gateway-prod-ap-northeast-0.grafana.net/otlp
    protocol: http
    auth:
      type: basic
      username: "${OTLP_USERNAME}"
      password: ${API_TOKEN}
    metrics:
      enabled: true
    logs:
      enabled: true
    traces:
      enabled: true
clusterMetrics:
  enabled: true
  opencost:
    enabled: true
    metricsSource: grafana-cloud-metrics
    opencost:
      exporter:
        defaultClusterId: k8s-myhome
      prometheus:
        existingSecretName: grafana-cloud-metrics-grafana-k8s-monitoring
        external:
          url: https://prometheus-prod-49-prod-ap-northeast-0.grafana.net/api/prom
  kepler:
    enabled: false  # VM環境では動作しない
clusterEvents:
  enabled: true
podLogs:
  enabled: true
applicationObservability:
  enabled: true
  receivers:
    otlp:
      grpc:
        enabled: true
        port: 4317
      http:
        enabled: true
        port: 4318
    zipkin:
      enabled: true
      port: 9411
alloy-metrics:
  enabled: true
  alloy:
    extraEnv:
      - name: GCLOUD_RW_API_KEY
        valueFrom:
          secretKeyRef:
            name: grafana-cloud-monitoring
            key: api-token
      - name: CLUSTER_NAME
        value: k8s-myhome
      - name: NAMESPACE
        valueFrom:
          fieldRef:
            fieldPath: metadata.namespace
      - name: POD_NAME
        valueFrom:
          fieldRef:
            fieldPath: metadata.name
      - name: GCLOUD_FM_COLLECTOR_ID
        value: grafana-k8s-monitoring-\$(CLUSTER_NAME)-\$(NAMESPACE)-\$(POD_NAME)
  remoteConfig:
    enabled: true
    url: https://fleet-management-prod-019.grafana.net
    auth:
      type: existingSecret
      existingSecretName: grafana-cloud-monitoring
      existingSecretUsernameKey: otlp-username
      existingSecretPasswordKey: api-token
alloy-singleton:
  enabled: true
  alloy:
    extraEnv:
      - name: GCLOUD_RW_API_KEY
        valueFrom:
          secretKeyRef:
            name: grafana-cloud-monitoring
            key: api-token
      - name: CLUSTER_NAME
        value: k8s-myhome
      - name: NAMESPACE
        valueFrom:
          fieldRef:
            fieldPath: metadata.namespace
      - name: POD_NAME
        valueFrom:
          fieldRef:
            fieldPath: metadata.name
      - name: GCLOUD_FM_COLLECTOR_ID
        value: grafana-k8s-monitoring-\$(CLUSTER_NAME)-\$(NAMESPACE)-\$(POD_NAME)
  remoteConfig:
    enabled: true
    url: https://fleet-management-prod-019.grafana.net
    auth:
      type: existingSecret
      existingSecretName: grafana-cloud-monitoring
      existingSecretUsernameKey: otlp-username
      existingSecretPasswordKey: api-token
alloy-logs:
  enabled: true
  alloy:
    extraEnv:
      - name: GCLOUD_RW_API_KEY
        valueFrom:
          secretKeyRef:
            name: grafana-cloud-monitoring
            key: api-token
      - name: CLUSTER_NAME
        value: k8s-myhome
      - name: NAMESPACE
        valueFrom:
          fieldRef:
            fieldPath: metadata.namespace
      - name: POD_NAME
        valueFrom:
          fieldRef:
            fieldPath: metadata.name
      - name: NODE_NAME
        valueFrom:
          fieldRef:
            fieldPath: spec.nodeName
      - name: GCLOUD_FM_COLLECTOR_ID
        value: grafana-k8s-monitoring-\$(CLUSTER_NAME)-\$(NAMESPACE)-alloy-logs-\$(NODE_NAME)
  remoteConfig:
    enabled: true
    url: https://fleet-management-prod-019.grafana.net
    auth:
      type: existingSecret
      existingSecretName: grafana-cloud-monitoring
      existingSecretUsernameKey: otlp-username
      existingSecretPasswordKey: api-token
alloy-receiver:
  enabled: true
  alloy:
    extraPorts:
      - name: otlp-grpc
        port: 4317
        targetPort: 4317
        protocol: TCP
      - name: otlp-http
        port: 4318
        targetPort: 4318
        protocol: TCP
      - name: zipkin
        port: 9411
        targetPort: 9411
        protocol: TCP
    extraEnv:
      - name: GCLOUD_RW_API_KEY
        valueFrom:
          secretKeyRef:
            name: grafana-cloud-monitoring
            key: api-token
      - name: CLUSTER_NAME
        value: k8s-myhome
      - name: NAMESPACE
        valueFrom:
          fieldRef:
            fieldPath: metadata.namespace
      - name: POD_NAME
        valueFrom:
          fieldRef:
            fieldPath: metadata.name
      - name: NODE_NAME
        valueFrom:
          fieldRef:
            fieldPath: spec.nodeName
      - name: GCLOUD_FM_COLLECTOR_ID
        value: grafana-k8s-monitoring-\$(CLUSTER_NAME)-\$(NAMESPACE)-alloy-receiver-\$(NODE_NAME)
  remoteConfig:
    enabled: true
    url: https://fleet-management-prod-019.grafana.net
    auth:
      type: existingSecret
      existingSecretName: grafana-cloud-monitoring
      existingSecretUsernameKey: otlp-username
      existingSecretPasswordKey: api-token
VALUES_EOF

echo "✓ Values ファイル作成完了"
EOF

# Helm リポジトリ追加とデプロイ
log_status "Grafana k8s-monitoring をデプロイ中..."
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << 'EOF'
# Helm リポジトリ追加
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update

# Grafana k8s-monitoring をインストール
echo "Grafana k8s-monitoring Helm chart をインストール中..."
helm upgrade --install grafana-k8s-monitoring grafana/k8s-monitoring \
  --namespace monitoring \
  -f /tmp/grafana-k8s-monitoring-values.yaml \
  --timeout 10m \
  --wait || echo "Grafana k8s-monitoring インストール継続中..."

# Pod の起動を待機
echo "Grafana k8s-monitoring Pod 起動待機中..."
sleep 30

# Pod の状態確認
echo "Grafana k8s-monitoring Pod 状態:"
kubectl get pods -n monitoring

# すべての Pod が Running になるまで待機（最大3分）
for i in {1..18}; do
    PENDING_PODS=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -v Running | wc -l || echo "0")
    if [ "$PENDING_PODS" -eq "0" ]; then
        echo "✓ すべての Grafana k8s-monitoring Pod が起動しました"
        break
    fi
    echo "Pod 起動待機中... (残り Pending: $PENDING_PODS)"
    sleep 10
done

echo "✓ Grafana k8s-monitoring デプロイ完了"
echo ""
echo "デプロイされたコンポーネント:"
echo "  - kube-state-metrics: クラスターメトリクス収集"
echo "  - Node Exporter: ノードメトリクス収集"
echo "  - Alloy metrics: メトリクス収集・送信"
echo "  - Alloy logs: ログ収集・送信"
echo "  - Alloy singleton: イベント収集"
echo "  - Alloy receiver: OTLP/Zipkinトレース受信"
echo "  - OpenCost: コスト分析"
echo ""
echo "アプリケーションテレメトリーエンドポイント:"
echo "  - OTLP gRPC: http://grafana-k8s-monitoring-alloy-receiver.monitoring.svc.cluster.local:4317"
echo "  - OTLP HTTP: http://grafana-k8s-monitoring-alloy-receiver.monitoring.svc.cluster.local:4318"
echo "  - Zipkin: http://grafana-k8s-monitoring-alloy-receiver.monitoring.svc.cluster.local:9411"
EOF

log_status "✓ Grafana k8s-monitoring デプロイ完了"
log_status ""
log_status "🎉 Grafana Cloud への監視機能が有効になりました！"
log_status "Grafana Cloud でメトリクス、ログ、トレースを確認してください"