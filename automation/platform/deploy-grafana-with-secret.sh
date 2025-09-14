#!/bin/bash
# Grafana k8s-monitoring デプロイスクリプト（Secret使用版）
# grafana-cloud-monitoring Secretから認証情報を取得してデプロイ

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

# grafana-cloud-monitoring Secret確認
log_info "grafana-cloud-monitoring Secretを確認中..."
if ! ssh k8suser@192.168.122.10 'kubectl get secret grafana-cloud-monitoring -n monitoring' &>/dev/null; then
    log_error "grafana-cloud-monitoring Secretが存在しません"
    exit 1
fi

# API Token取得
log_info "API Tokenを取得中..."
API_TOKEN=$(ssh k8suser@192.168.122.10 'kubectl get secret grafana-cloud-monitoring -n monitoring -o jsonpath="{.data.api-token}" | base64 -d')

if [[ -z "$API_TOKEN" ]]; then
    log_error "API Tokenを取得できませんでした"
    exit 1
fi

log_info "API Token取得成功（長さ: ${#API_TOKEN}文字）"

# 固定ユーザー名
METRICS_USERNAME="2666273"
LOGS_USERNAME="1328813"
OTLP_USERNAME="1371019"

# 既存のリリースを削除
log_info "既存のGrafana k8s-monitoringリリースを削除中..."
ssh k8suser@192.168.122.10 'helm uninstall grafana-k8s-monitoring -n monitoring 2>/dev/null || true'
sleep 10

# Grafana k8s-monitoring デプロイ
log_info "Grafana k8s-monitoring を再デプロイ中..."
ssh k8suser@192.168.122.10 "helm upgrade --install --atomic --timeout 300s grafana-k8s-monitoring grafana/k8s-monitoring \
  --namespace monitoring --create-namespace --values - <<EOF
cluster:
  name: home-k8s

destinations:
  - name: grafana-cloud-metrics
    type: prometheus
    url: https://prometheus-prod-49-prod-ap-northeast-0.grafana.net./api/prom/push
    auth:
      type: basic
      username: \"${METRICS_USERNAME}\"
      password: \"${API_TOKEN}\"
  - name: grafana-cloud-logs
    type: loki
    url: https://logs-prod-030.grafana.net./loki/api/v1/push
    auth:
      type: basic
      username: \"${LOGS_USERNAME}\"
      password: \"${API_TOKEN}\"
  - name: gc-otlp-endpoint
    type: otlp
    url: https://otlp-gateway-prod-ap-northeast-0.grafana.net./otlp
    protocol: http
    auth:
      type: basic
      username: \"${OTLP_USERNAME}\"
      password: \"${API_TOKEN}\"
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
        value: \"${API_TOKEN}\"
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
        value: grafana-k8s-monitoring-\\\$(CLUSTER_NAME)-\\\$(NAMESPACE)-\\\$(POD_NAME)

alloy-singleton:
  enabled: true
  alloy:
    extraEnv:
      - name: GCLOUD_RW_API_KEY
        value: \"${API_TOKEN}\"
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
        value: grafana-k8s-monitoring-\\\$(CLUSTER_NAME)-\\\$(NAMESPACE)-\\\$(POD_NAME)

alloy-logs:
  enabled: true
  alloy:
    extraEnv:
      - name: GCLOUD_RW_API_KEY
        value: \"${API_TOKEN}\"
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
        value: grafana-k8s-monitoring-\\\$(CLUSTER_NAME)-\\\$(NAMESPACE)-alloy-logs-\\\$(NODE_NAME)

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
        value: \"${API_TOKEN}\"
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
        value: grafana-k8s-monitoring-\\\$(CLUSTER_NAME)-\\\$(NAMESPACE)-alloy-receiver-\\\$(NODE_NAME)
EOF"

if [ $? -eq 0 ]; then
    log_info "✅ Grafana k8s-monitoring デプロイ成功"
    log_info "API Tokenを使用してGrafana Cloudに接続しています"
    
    # デプロイ状態確認
    log_info "デプロイ状態:"
    ssh k8suser@192.168.122.10 'kubectl get pods -n monitoring'
else
    log_error "Grafana k8s-monitoring デプロイに失敗しました"
    exit 1
fi