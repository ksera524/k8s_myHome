#!/bin/bash

# Grafana k8s-monitoring デプロイスクリプト
# Grafana Cloudへの監視機能を自動セットアップ

set -euo pipefail

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_status() { echo -e "${GREEN}$1${NC}"; }
log_error() { echo -e "${RED}$1${NC}"; }
log_warning() { echo -e "${YELLOW}$1${NC}"; }

# kubectl実行関数（SSH経由またはローカル）
USE_SSH=false
kubectl_exec() {
    if [ "$USE_SSH" = true ]; then
        ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} "kubectl $@"
    else
        kubectl "$@"
    fi
}

# helm実行関数（SSH経由またはローカル）
helm_exec() {
    if [ "$USE_SSH" = true ]; then
        ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} "helm $@"
    else
        helm "$@"
    fi
}

# ファイルコピー関数（SSH経由またはローカル）
copy_to_cluster() {
    local src=$1
    local dest=$2
    if [ "$USE_SSH" = true ]; then
        scp -o StrictHostKeyChecking=no "$src" k8suser@${CONTROL_PLANE_IP}:"$dest"
    else
        cp "$src" "$dest"
    fi
}

# IPアドレス設定
CONTROL_PLANE_IP="${K8S_CONTROL_PLANE_IP:-192.168.122.10}"

log_status "=== Grafana k8s-monitoring デプロイ開始 ==="
log_status "デバッグ情報:"
log_status "  NON_INTERACTIVE: ${NON_INTERACTIVE:-未設定}"
log_status "  CONTROL_PLANE_IP: ${CONTROL_PLANE_IP}"
log_status "  実行ディレクトリ: $(pwd)"
log_status "  実行ユーザー: $(whoami)"

# 前提条件確認
log_status "前提条件を確認中..."

# k8sクラスタ接続確認と接続方法の決定
log_status "k8sクラスタ接続確認中..."
if ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=10 k8suser@${CONTROL_PLANE_IP} 'kubectl get nodes' >/dev/null 2>&1; then
    log_status "✓ SSH経由でk8sクラスタ接続確認完了"
    USE_SSH=true
else
    log_warning "⚠️  SSH接続に失敗しました。ローカルからの接続を試みます"
    # ローカルのkubeconfigを確認
    if [ -f "$HOME/.kube/config" ] && kubectl get nodes >/dev/null 2>&1; then
        log_status "✓ ローカルkubeconfigで接続可能"
        USE_SSH=false
    else
        log_warning "⚠️  ローカル接続も失敗。SSH経由で再試行します"
        USE_SSH=true
        # 最終確認
        if ! ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=5 k8suser@${CONTROL_PLANE_IP} 'true' 2>/dev/null; then
            log_error "❌ k8sクラスタに接続できません。スクリプトを終了します"
            log_error "後で手動実行してください: ./deploy-grafana-monitoring.sh"
            exit 1
        fi
    fi
fi

log_status "接続モード: $([ "$USE_SSH" = true ] && echo 'SSH経由' || echo 'ローカル')"

# External Secrets Operator確認と起動待機
log_status "External Secrets Operator確認中..."

# ArgoCD経由でESOがデプロイされるまで待機（最大120秒）
log_status "External Secrets Operatorの起動待機中..."
for i in {1..24}; do
    # 正しいラベルを使用してESO Podを検索（より確実な方法）
    ESO_POD_OUTPUT=$(kubectl_exec get pods -n external-secrets-system -l app.kubernetes.io/name=external-secrets --no-headers 2>/dev/null || echo "")
    if [ -n "$ESO_POD_OUTPUT" ]; then
        ESO_RUNNING=$(echo "$ESO_POD_OUTPUT" | grep -c "Running" || echo "0")
        ESO_TOTAL=$(echo "$ESO_POD_OUTPUT" | wc -l | tr -d ' ' || echo "0")
    else
        ESO_RUNNING="0"
        ESO_TOTAL="0"
    fi
    
    # 数値でない場合は0にリセット
    if ! [[ "$ESO_RUNNING" =~ ^[0-9]+$ ]]; then
        ESO_RUNNING="0"
    fi
    if ! [[ "$ESO_TOTAL" =~ ^[0-9]+$ ]]; then
        ESO_TOTAL="0"
    fi
    
    # namespaceが存在しない場合
    if [ "$ESO_TOTAL" -eq "0" ]; then
        # namespaceが存在するか確認
        if ! kubectl_exec get namespace external-secrets-system >/dev/null 2>&1; then
            echo "  ESO待機中... ($i/24) - Namespace: 未作成"
        else
            echo "  ESO待機中... ($i/24) - Pod: デプロイ待ち"
        fi
    else
        echo "  ESO待機中... ($i/24) - Pod: $ESO_RUNNING/$ESO_TOTAL"
    fi
    
    # CRDがインストールされているか確認
    CRD_EXISTS=$(kubectl_exec get crd externalsecrets.external-secrets.io 2>/dev/null | grep -c externalsecrets | tr -d '\n\r ' || echo "0")
    if ! [[ "$CRD_EXISTS" =~ ^[0-9]+$ ]]; then
        CRD_EXISTS="0"
    fi
    
    if [ "$ESO_TOTAL" -gt "0" ] && [ "$ESO_RUNNING" -gt "0" ] && [ "$CRD_EXISTS" -gt "0" ]; then
        log_status "✓ External Secrets Operator Podが起動し、CRDがインストールされました"
        break
    fi
    
    if [ "$i" -eq "24" ]; then
        log_warning "⚠️ External Secrets Operatorの起動待機がタイムアウトしました"
        log_warning "Pod状態: Running=$ESO_RUNNING, Total=$ESO_TOTAL"
        log_warning "CRD状態: $([ "$CRD_EXISTS" -gt "0" ] && echo "インストール済み" || echo "未インストール")"
        
        # CRDがない場合の処理
        if [ "$CRD_EXISTS" -eq "0" ]; then
            log_warning "⚠️ External Secrets CRDがインストールされていません"
            log_warning "External Secrets Operatorの手動デプロイを試みます..."
            
            # ArgoCDアプリケーションの同期を試行
            if kubectl_exec get application external-secrets-operator -n argocd >/dev/null 2>&1; then
                log_status "ArgoCD経由でExternal Secrets Operatorを同期中..."
                kubectl_exec patch application external-secrets-operator -n argocd --type merge -p '{"spec":{"syncPolicy":{"syncOptions":["CreateNamespace=true"]}}}' || true
                kubectl_exec -n argocd get application external-secrets-operator -o jsonpath='{.status.sync.status}' || true
                sleep 10
                
                # 再度CRDを確認
                CRD_EXISTS=$(kubectl_exec get crd externalsecrets.external-secrets.io 2>/dev/null | grep -c externalsecrets | tr -d '\n\r ' || echo "0")
                if [ "$CRD_EXISTS" -eq "0" ]; then
                    log_error "❌ External Secrets CRDのインストールに失敗しました"
                    log_error "プラットフォームデプロイを再実行してください: make platform"
                    exit 1
                fi
            else
                log_error "❌ ArgoCD external-secrets-operatorアプリケーションが見つかりません"
                log_error "プラットフォームデプロイを再実行してください: make platform"
                exit 1
            fi
        fi
    fi
    sleep 5
done

# ClusterSecretStoreの起動待機（最大60秒）
log_status "ClusterSecretStoreの起動待機中..."
for i in {1..12}; do
    if kubectl_exec get clustersecretstore pulumi-esc-store >/dev/null 2>&1; then
        STORE_STATUS=$(kubectl_exec get clustersecretstore pulumi-esc-store -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        if [ "$STORE_STATUS" = "True" ]; then
            log_status "✓ ClusterSecretStore pulumi-esc-store Ready"
            break
        else
            echo "  ClusterSecretStore待機中... ($i/12) - Status: $STORE_STATUS"
        fi
    else
        echo "  ClusterSecretStore待機中... ($i/12) - 未作成"
    fi
    
    if [ "$i" -eq "12" ]; then
        log_warning "⚠️ ClusterSecretStoreがReadyになりませんでした"
        log_warning "しかし、デプロイは継続します"
    fi
    sleep 5
done

log_status "✓ External Secrets Operator準備完了"

# External Secret マニフェストをコピー
log_status "External Secret マニフェストを適用中..."
copy_to_cluster "../../manifests/config/secrets/grafana-monitoring-externalsecret.yaml" "/tmp/grafana-monitoring-externalsecret.yaml"

# monitoring namespace作成
kubectl_exec create namespace monitoring --dry-run=client -o yaml | kubectl_exec apply -f -

# External Secret適用
kubectl_exec apply -f /tmp/grafana-monitoring-externalsecret.yaml

# Secret作成待機
log_status "Grafana Cloud認証情報の同期待機中..."
for i in {1..30}; do
    if kubectl_exec get secret grafana-cloud-monitoring -n monitoring >/dev/null 2>&1; then
        log_status "✓ Grafana Cloud認証情報取得完了"
        break
    fi
    echo "Secret同期待機中... ($i/30)"
    sleep 5
done

# Secret存在確認
if ! kubectl_exec get secret grafana-cloud-monitoring -n monitoring >/dev/null 2>&1; then
    log_error "エラー: Grafana Cloud認証情報を取得できませんでした"
    log_error "Pulumi ESCに 'grafana' キーが設定されているか確認してください"
    exit 1
fi

# 認証情報取得（API Tokenのみ）
API_TOKEN=$(kubectl_exec get secret grafana-cloud-monitoring -n monitoring -o jsonpath='{.data.api-token}' | base64 -d)

if [[ -z "$API_TOKEN" ]]; then
    log_error "エラー: API Tokenを取得できませんでした"
    exit 1
fi

# ユーザー名は固定値
METRICS_USERNAME="2666273"
LOGS_USERNAME="1328813"
OTLP_USERNAME="1371019"

log_status "✓ 認証情報取得完了"

# Grafana k8s-monitoring values ファイル作成
log_status "Grafana k8s-monitoring values ファイル作成中..."

# Values ファイル作成（動作確認済み設定）
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

# クラスタメトリクス設定
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
    enabled: false  # CPU要件のため無効化
  node-exporter:
    enabled: false  # 既存のnode-exporterと競合するため無効化
    deploy: false

# クラスタイベント収集
clusterEvents:
  enabled: true

# Podログ収集
podLogs:
  enabled: true

# アプリケーション可観測性
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

# Alloyコンポーネント設定
alloy-metrics:
  enabled: true

alloy-singleton:
  enabled: true

alloy-logs:
  enabled: true

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
VALUES_EOF

copy_to_cluster "/tmp/grafana-k8s-monitoring-values.yaml" "/tmp/grafana-k8s-monitoring-values.yaml"
log_status "✓ Values ファイル作成完了"

# Helm リポジトリ追加とデプロイ
log_status "Grafana k8s-monitoring をデプロイ中..."

# デバッグ情報
log_status "Helmコマンド実行準備中..."
log_status "NON_INTERACTIVE: ${NON_INTERACTIVE:-未設定}"

# Helm リポジトリ追加
log_status "Helm リポジトリ追加中..."
if helm_exec repo add grafana https://grafana.github.io/helm-charts 2>/dev/null; then
    log_status "✓ Grafana Helm repository追加成功"
else
    log_warning "⚠️ Grafana Helm repository追加で警告（既存の可能性）"
fi

if helm_exec repo update; then
    log_status "✓ Helm repository更新成功"
else
    log_error "❌ Helm repository更新失敗"
    exit 1
fi

# 既存のリリースを確認
log_status "既存のGrafana k8s-monitoring リリース確認中..."
if helm_exec list -n monitoring | grep -q grafana-k8s-monitoring; then
    log_warning "⚠️ 既存のgrafana-k8s-monitoringリリースが見つかりました"
    log_status "既存リリースの状態:"
    helm_exec list -n monitoring | grep grafana-k8s-monitoring || true
    log_status "アップグレードを実行します..."
    HELM_ACTION="upgrade"
else
    log_status "✓ 新規インストールを実行します"
    HELM_ACTION="install"
fi

# Grafana k8s-monitoring をインストール/アップグレード
log_status "Grafana k8s-monitoring Helm chart を${HELM_ACTION}中..."
log_status "タイムアウト設定: 15分"

# NON_INTERACTIVE環境では--waitを使用せず、後でPod起動を確認
if helm_exec upgrade --install grafana-k8s-monitoring grafana/k8s-monitoring \
  --namespace monitoring \
  -f /tmp/grafana-k8s-monitoring-values.yaml \
  --timeout 15m \
  --create-namespace; then
    log_status "✓ Helm chart ${HELM_ACTION} 成功"
else
    HELM_EXIT_CODE=$?
    log_error "❌ Helm chart ${HELM_ACTION} 失敗 (exit code: $HELM_EXIT_CODE)"
    log_status "既存リリースの状態確認:"
    helm_exec list -n monitoring || true
    log_status "Pod状態確認:"
    kubectl_exec get pods -n monitoring || true
    exit 1
fi

log_status "Pod起動確認を実行中..."
# Pod の起動を待機
log_status "Grafana k8s-monitoring Pod 起動待機中..."
sleep 20

# Pod の状態確認
log_status "現在のPod状態:"
kubectl_exec get pods -n monitoring 2>/dev/null || log_warning "monitoring namespace内にPodが見つかりません"

# すべての Pod が Running になるまで待機（最大5分）
log_status "Pod起動完了待機中（最大5分）..."
for i in {1..30}; do
    # 全Pod数を取得
    TOTAL_PODS=$(kubectl_exec get pods -n monitoring --no-headers 2>/dev/null | wc -l || echo "0")
    # Running状態のPod数を取得（改行を除去）
    RUNNING_PODS=$(kubectl_exec get pods -n monitoring --no-headers 2>/dev/null | grep Running | wc -l | tr -d '\n\r ' || echo "0")
    # Pending/Error状態のPod数を取得（改行を除去）
    PENDING_PODS=$(kubectl_exec get pods -n monitoring --no-headers 2>/dev/null | grep -v Running | wc -l | tr -d '\n\r ' || echo "0")
    
    # 数値チェック
    if ! [[ "$RUNNING_PODS" =~ ^[0-9]+$ ]]; then
        RUNNING_PODS="0"
    fi
    if ! [[ "$PENDING_PODS" =~ ^[0-9]+$ ]]; then
        PENDING_PODS="0"
    fi
    
    echo "Pod状態確認 ($i/30): Total=$TOTAL_PODS, Running=$RUNNING_PODS, Others=$PENDING_PODS"
    
    if [ "$TOTAL_PODS" -gt "0" ] && [ "$PENDING_PODS" -eq "0" ]; then
        log_status "✓ すべての Grafana k8s-monitoring Pod が起動しました"
        break
    elif [ "$TOTAL_PODS" -eq "0" ]; then
        log_warning "⚠️ Podが見つかりません。Helmリリースを確認中..."
        helm_exec list -n monitoring | grep grafana || log_warning "Helmリリースが見つかりません"
    fi
    
    if [ "$i" -eq "30" ]; then
        log_warning "⚠️ Pod起動完了を待機中にタイムアウトしました"
        log_status "現在のPod状態:"
        kubectl_exec get pods -n monitoring 2>/dev/null || log_warning "Podの取得に失敗"
        log_warning "デプロイは継続しますが、手動でPod状態を確認してください"
    else
        sleep 10
    fi
done

log_status "✓ Grafana k8s-monitoring デプロイ処理完了"
echo ""
echo "デプロイされたコンポーネント:"
echo "  - kube-state-metrics: Kubernetesオブジェクトメトリクス収集"
echo "  - OpenCost: コスト監視・分析"
echo "  - Alloy metrics: メトリクス収集・送信（StatefulSet）"
echo "  - Alloy logs: ログ収集・送信（DaemonSet）"
echo "  - Alloy receiver: OTLP/Zipkinトレース受信（DaemonSet）"
echo "  - Alloy singleton: クラスタイベント収集（Deployment）"
echo ""
echo "アプリケーションテレメトリーエンドポイント:"
echo "  - OTLP gRPC: http://grafana-k8s-monitoring-alloy-receiver.monitoring.svc.cluster.local:4317"
echo "  - OTLP HTTP: http://grafana-k8s-monitoring-alloy-receiver.monitoring.svc.cluster.local:4318"
echo "  - Zipkin: http://grafana-k8s-monitoring-alloy-receiver.monitoring.svc.cluster.local:9411"

log_status "✓ Grafana k8s-monitoring デプロイ完了"
log_status ""
log_status "🎉 Grafana Cloud への監視機能が有効になりました！"
log_status "Grafana Cloud でメトリクス、ログ、トレースを確認してください"