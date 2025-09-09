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

# デバッグ情報出力
log_status "デバッグ情報:"
log_status "  NON_INTERACTIVE: ${NON_INTERACTIVE:-未設定}"
log_status "  CONTROL_PLANE_IP: $CONTROL_PLANE_IP"
log_status "  実行ディレクトリ: $(pwd)"
log_status "  実行ユーザー: $(whoami)"

# 前提条件確認
log_status "前提条件を確認中..."

# k8sクラスタ接続確認
log_status "k8sクラスタ接続確認中..."
if ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=10 k8suser@${CONTROL_PLANE_IP} 'kubectl get nodes' >/dev/null 2>&1; then
    log_status "✓ k8sクラスタ接続確認完了"
else
    log_error "❌ k8sクラスタに接続できません"
    log_error "接続先: k8suser@${CONTROL_PLANE_IP}"
    log_error "SSH接続を確認してください"
    exit 1
fi

# External Secrets Operator確認
log_status "External Secrets Operator確認中..."
if ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << 'EOF'
echo "External Secrets Operator状態確認中..."

# ESO Deployment確認
if kubectl get deployment -n external-secrets-system external-secrets-operator >/dev/null 2>&1; then
    echo "✓ External Secrets Operator Deployment存在確認"
    # Pod状態確認
    ESO_READY=$(kubectl get pods -n external-secrets-system -l app.kubernetes.io/name=external-secrets --no-headers 2>/dev/null | grep Running | wc -l)
    echo "✓ ESO Running Pods: $ESO_READY"
    if [ "$ESO_READY" -eq "0" ]; then
        echo "⚠️ 警告: ESO Podが Running 状態ではありません"
        kubectl get pods -n external-secrets-system -l app.kubernetes.io/name=external-secrets 2>/dev/null || echo "ESO Podが見つかりません"
    fi
else
    echo "❌ エラー: External Secrets Operatorがインストールされていません"
    exit 1
fi

# ClusterSecretStore確認
if kubectl get clustersecretstore pulumi-esc-store >/dev/null 2>&1; then
    echo "✓ ClusterSecretStore pulumi-esc-store存在確認"
    # Ready状態確認
    STORE_READY=$(kubectl get clustersecretstore pulumi-esc-store -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    echo "✓ ClusterSecretStore Ready状態: $STORE_READY"
    if [ "$STORE_READY" != "True" ]; then
        echo "⚠️ 警告: ClusterSecretStoreがReady状態ではありません"
        echo "しかし、デプロイは継続します（Secretが同期される可能性があります）"
    fi
else
    echo "❌ エラー: ClusterSecretStore pulumi-esc-storeが存在しません"
    echo "External Secrets経由でGrafana認証情報を取得できません"
    exit 1
fi

echo "✓ External Secrets Operator準備完了"
EOF
then
    log_status "✓ External Secrets Operator確認完了"
else
    ESO_EXIT_CODE=$?
    log_error "❌ External Secrets Operator確認失敗 (exit code: $ESO_EXIT_CODE)"
    exit 1
fi

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

# Values ファイル作成（remoteConfigを無効化してシンプルに）
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
      password: "${API_TOKEN}"
  - name: grafana-cloud-logs
    type: loki
    url: https://logs-prod-030.grafana.net/loki/api/v1/push
    auth:
      type: basic
      username: "${LOGS_USERNAME}"
      password: "${API_TOKEN}"
  - name: gc-otlp-endpoint
    type: otlp
    url: https://otlp-gateway-prod-ap-northeast-0.grafana.net/otlp
    protocol: http
    auth:
      type: basic
      username: "${OTLP_USERNAME}"
      password: "${API_TOKEN}"
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
      - name: CLUSTER_NAME
        value: k8s-myhome
  remoteConfig:
    enabled: false  # remoteConfigを無効化
alloy-singleton:
  enabled: true
  alloy:
    extraEnv:
      - name: CLUSTER_NAME
        value: k8s-myhome
  remoteConfig:
    enabled: false  # remoteConfigを無効化
alloy-logs:
  enabled: true
  alloy:
    extraEnv:
      - name: CLUSTER_NAME
        value: k8s-myhome
  remoteConfig:
    enabled: false  # remoteConfigを無効化
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
      - name: CLUSTER_NAME
        value: k8s-myhome
  remoteConfig:
    enabled: false  # remoteConfigを無効化
VALUES_EOF

echo "✓ Values ファイル作成完了"
EOF

# Helm リポジトリ追加とデプロイ
log_status "Grafana k8s-monitoring をデプロイ中..."
if ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << 'EOF'
# デバッグ情報
echo "Helmコマンド実行準備中..."
echo "NON_INTERACTIVE: ${NON_INTERACTIVE:-未設定}"

# Helm リポジトリ追加
echo "Helm リポジトリ追加中..."
if helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null; then
    echo "✓ Grafana Helm repository追加成功"
else
    echo "⚠️ Grafana Helm repository追加で警告（既存の可能性）"
fi

if helm repo update; then
    echo "✓ Helm repository更新成功"
else
    echo "❌ Helm repository更新失敗"
    exit 1
fi

# 既存のリリースを確認
echo "既存のGrafana k8s-monitoring リリース確認中..."
if helm list -n monitoring | grep -q grafana-k8s-monitoring; then
    echo "⚠️ 既存のgrafana-k8s-monitoringリリースが見つかりました"
    echo "既存リリースの状態:"
    helm list -n monitoring | grep grafana-k8s-monitoring || true
    echo "アップグレードを実行します..."
    HELM_ACTION="upgrade"
else
    echo "✓ 新規インストールを実行します"
    HELM_ACTION="install"
fi

# Grafana k8s-monitoring をインストール/アップグレード
echo "Grafana k8s-monitoring Helm chart を${HELM_ACTION}中..."
echo "タイムアウト設定: 15分"

# NON_INTERACTIVE環境では--waitを使用せず、後でPod起動を確認
if helm upgrade --install grafana-k8s-monitoring grafana/k8s-monitoring \
  --namespace monitoring \
  -f /tmp/grafana-k8s-monitoring-values.yaml \
  --timeout 15m \
  --create-namespace; then
    echo "✓ Helm chart ${HELM_ACTION} 成功"
else
    HELM_EXIT_CODE=$?
    echo "❌ Helm chart ${HELM_ACTION} 失敗 (exit code: $HELM_EXIT_CODE)"
    echo "既存リリースの状態確認:"
    helm list -n monitoring || true
    echo "Pod状態確認:"
    kubectl get pods -n monitoring || true
    exit 1
fi
EOF
then
    log_status "✓ Helm chart デプロイ成功"
else
    HELM_DEPLOY_EXIT_CODE=$?
    log_error "❌ Helm chart デプロイ失敗 (exit code: $HELM_DEPLOY_EXIT_CODE)"
    exit 1
fi

log_status "Pod起動確認を実行中..."
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << 'EOF'
# Pod の起動を待機
echo "Grafana k8s-monitoring Pod 起動待機中..."
sleep 20

# Pod の状態確認
echo "現在のPod状態:"
kubectl get pods -n monitoring 2>/dev/null || echo "monitoring namespace内にPodが見つかりません"

# すべての Pod が Running になるまで待機（最大5分）
echo "Pod起動完了待機中（最大5分）..."
for i in {1..30}; do
    # 全Pod数を取得
    TOTAL_PODS=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | wc -l || echo "0")
    # Running状態のPod数を取得
    RUNNING_PODS=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep Running | wc -l || echo "0")
    # Pending/Error状態のPod数を取得
    PENDING_PODS=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -v Running | wc -l || echo "0")
    
    echo "Pod状態確認 ($i/30): Total=$TOTAL_PODS, Running=$RUNNING_PODS, Others=$PENDING_PODS"
    
    if [ "$TOTAL_PODS" -gt "0" ] && [ "$PENDING_PODS" -eq "0" ]; then
        echo "✓ すべての Grafana k8s-monitoring Pod が起動しました"
        break
    elif [ "$TOTAL_PODS" -eq "0" ]; then
        echo "⚠️ 警告: Podが見つかりません。Helmリリースを確認中..."
        helm list -n monitoring | grep grafana || echo "Helmリリースが見つかりません"
    fi
    
    if [ "$i" -eq "30" ]; then
        echo "⚠️ 警告: Pod起動完了を待機中にタイムアウトしました"
        echo "現在のPod状態:"
        kubectl get pods -n monitoring 2>/dev/null || echo "Podの取得に失敗"
        echo "デプロイは継続しますが、手動でPod状態を確認してください"
    else
        sleep 10
    fi
done

echo "✓ Grafana k8s-monitoring デプロイ処理完了"
EOF
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