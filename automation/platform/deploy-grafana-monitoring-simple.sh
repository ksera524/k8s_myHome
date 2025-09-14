#!/bin/bash
# Grafana k8s-monitoring デプロイスクリプト（シンプル版）
# 参考値をハードコードして直接デプロイ

set -euo pipefail

# 色付き出力用
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}ℹ️ ${1}${NC}"
}

log_error() {
    echo -e "${RED}❌ ${1}${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️ ${1}${NC}"
}

# クラスタ接続確認
log_info "Kubernetesクラスタ接続確認中..."
if ! ssh k8suser@192.168.122.10 'kubectl get nodes' &>/dev/null; then
    log_error "Kubernetesクラスタに接続できません"
    exit 1
fi

# Helm リポジトリ追加
log_info "Grafana Helm リポジトリを追加中..."
ssh k8suser@192.168.122.10 'helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true'
ssh k8suser@192.168.122.10 'helm repo update'

# monitoring namespace作成
log_info "monitoring namespaceを作成中..."
ssh k8suser@192.168.122.10 'kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -'

# Grafana k8s-monitoring デプロイ
log_info "Grafana k8s-monitoring をデプロイ中..."
ssh k8suser@192.168.122.10 'helm upgrade --install --atomic --timeout 300s grafana-k8s-monitoring grafana/k8s-monitoring \
  --namespace monitoring --create-namespace --values - <<EOF
cluster:
  name: home-k8s

destinations:
  - name: grafana-cloud-metrics
    type: prometheus
    url: https://prometheus-prod-49-prod-ap-northeast-0.grafana.net./api/prom/push
    auth:
      type: basic
      username: "2666273"
      password: "DUMMY_TOKEN_REPLACE_WITH_REAL"
  - name: grafana-cloud-logs
    type: loki
    url: https://logs-prod-030.grafana.net./loki/api/v1/push
    auth:
      type: basic
      username: "1328813"
      password: "DUMMY_TOKEN_REPLACE_WITH_REAL"
  - name: gc-otlp-endpoint
    type: otlp
    url: https://otlp-gateway-prod-ap-northeast-0.grafana.net./otlp
    protocol: http
    auth:
      type: basic
      username: "1371019"
      password: "DUMMY_TOKEN_REPLACE_WITH_REAL"
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
        defaultClusterId: home-k8s
      prometheus:
        existingSecretName: grafana-cloud-metrics-grafana-k8s-monitoring
        external:
          url: https://prometheus-prod-49-prod-ap-northeast-0.grafana.net./api/prom
  kepler:
    enabled: false

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
        value: "DUMMY_TOKEN_REPLACE_WITH_REAL"
      - name: CLUSTER_NAME
        value: home-k8s
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

alloy-singleton:
  enabled: true
  alloy:
    extraEnv:
      - name: GCLOUD_RW_API_KEY
        value: "DUMMY_TOKEN_REPLACE_WITH_REAL"
      - name: CLUSTER_NAME
        value: home-k8s
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

alloy-logs:
  enabled: true
  alloy:
    extraEnv:
      - name: GCLOUD_RW_API_KEY
        value: "DUMMY_TOKEN_REPLACE_WITH_REAL"
      - name: CLUSTER_NAME
        value: home-k8s
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
        value: "DUMMY_TOKEN_REPLACE_WITH_REAL"
      - name: CLUSTER_NAME
        value: home-k8s
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
EOF'

if [ $? -eq 0 ]; then
    log_info "✅ Grafana k8s-monitoring デプロイ成功"
    log_warning "注意: 現在はダミートークンを使用しています。実際のトークンに置き換えてください。"
    
    # デプロイ状態確認
    log_info "デプロイ状態:"
    ssh k8suser@192.168.122.10 'kubectl get pods -n monitoring'
else
    log_error "Grafana k8s-monitoring デプロイに失敗しました"
    exit 1
fi