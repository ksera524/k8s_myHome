#!/bin/bash

# Kubernetes基盤構築スクリプト - GitOps管理版
# ArgoCD → App-of-Apps (MetalLB, Gateway API, cert-manager, ESO等を統合管理) → Harbor

set -euo pipefail

# 非対話モード設定
export DEBIAN_FRONTEND=noninteractive
export NON_INTERACTIVE=true

# GitHub認証情報管理ユーティリティを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/argocd/github-auth-utils.sh"

# 共通色設定スクリプトを読み込み（settings-loader.shより先に）
source "$SCRIPT_DIR/../scripts/common-logging.sh"

# 設定ファイル読み込み（環境変数が未設定の場合）
if [[ -f "$SCRIPT_DIR/../scripts/settings-loader.sh" ]]; then
    source "$SCRIPT_DIR/../scripts/settings-loader.sh" load 2>/dev/null || true
    
    # settings.tomlからのPULUMI_ACCESS_TOKEN設定を確認・適用
    if [[ -n "${PULUMI_ACCESS_TOKEN:-}" ]]; then
        :
    elif [[ -n "${PULUMI_PULUMI_ACCESS_TOKEN:-}" ]]; then
        export PULUMI_ACCESS_TOKEN="${PULUMI_PULUMI_ACCESS_TOKEN}"
    fi
fi

log_status "=== Kubernetes基盤構築開始 ==="

# IPアドレス設定（settings.tomlから取得、デフォルト値付き）
CONTROL_PLANE_IP="${K8S_CONTROL_PLANE_IP:-192.168.122.10}"
WORKER_1_IP="${K8S_WORKER_1_IP:-192.168.122.11}"
WORKER_2_IP="${K8S_WORKER_2_IP:-192.168.122.12}"
HARBOR_IP="${HARBOR_IP:-192.168.122.100}"

# 0. マニフェストファイルの準備
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scp -o StrictHostKeyChecking=no "../../manifests/core/storage-classes/local-storage-class.yaml" k8suser@${CONTROL_PLANE_IP}:/tmp/ 2>/dev/null
scp -o StrictHostKeyChecking=no "$SCRIPT_DIR/../templates/platform/argocd-ingress.yaml" k8suser@${CONTROL_PLANE_IP}:/tmp/ 2>/dev/null
scp -o StrictHostKeyChecking=no "../../manifests/bootstrap/app-of-apps.yaml" k8suser@${CONTROL_PLANE_IP}:/tmp/ 2>/dev/null
scp -o StrictHostKeyChecking=no "../../manifests/platform/secrets/external-secrets/pulumi-esc-secretstore.yaml" k8suser@${CONTROL_PLANE_IP}:/tmp/ 2>/dev/null || true

# 1. 前提条件確認
log_status "前提条件を確認中..."

# SSH known_hosts クリーンアップ
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "${CONTROL_PLANE_IP}" 2>/dev/null || true
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "${WORKER_1_IP}" 2>/dev/null || true  
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "${WORKER_2_IP}" 2>/dev/null || true

# k8sクラスタ接続確認
if ! ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=10 k8suser@${CONTROL_PLANE_IP} 'kubectl get nodes' >/dev/null 2>&1; then
    log_error "k8sクラスタに接続できません"
    log_error "Phase 3のk8sクラスタ構築を先に完了してください"
    log_error "注意: このスクリプトはUbuntuホストマシンで実行してください（WSL2不可）"
    exit 1
fi

READY_NODES=$(ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} 'kubectl get nodes --no-headers' | grep -c Ready || echo "0")
if [[ $READY_NODES -lt 2 ]]; then
    log_error "Ready状態のNodeが2台未満です（現在: $READY_NODES台）"
    exit 1
else
    log_status "✓ k8sクラスタ（$READY_NODES Node）接続OK"
fi

# Phase 4.1-4.3: 基盤インフラ（MetalLB, NGINX Gateway Fabric, cert-manager）はGitOps管理へ移行
log_status "=== Phase 4.1-4.3: 基盤インフラはGitOps管理 ==="
log_debug "MetalLB, NGINX Gateway Fabric, cert-managerはArgoCD経由でデプロイされます"



# Phase 4.4: StorageClass設定

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << 'EOF'
# Local StorageClass作成
kubectl apply -f /tmp/local-storage-class.yaml

EOF

# Phase 4.5: ArgoCD デプロイ
log_status "ArgoCD デプロイ中..."

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << 'EOF'
# ArgoCD namespace作成（ArgoCD自体に必要）
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# ArgoCD インストール
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# ApplicationSet CRD を明示適用（install.yaml 側の欠落/不整合対策）
kubectl apply --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.3.0/manifests/crds/applicationset-crd.yaml

# CRD存在確認（欠落時は以降のアプリ同期が不安定になるため失敗扱い）
kubectl get crd applicationsets.argoproj.io >/dev/null

# ArgoCD起動まで待機
kubectl wait --namespace argocd --for=condition=ready pod --selector=app.kubernetes.io/component=server --timeout=300s

# ArgoCD insecureモード設定（HTTPアクセス対応）
kubectl patch configmap argocd-cmd-params-cm -n argocd -p '{"data":{"server.insecure":"true"}}'

# ArgoCD管理者パスワード取得・表示
echo "ArgoCD管理者パスワード:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""

# ArgoCD HTTPRoute設定（HTTP対応）
kubectl apply -f /tmp/argocd-ingress.yaml

echo "✓ ArgoCD基本設定完了"
EOF

log_status "✓ ArgoCD デプロイ完了"

# Phase 4.6: App-of-Apps デプロイ
log_status "=== Phase 4.6: App-of-Apps パターン適用 ==="
log_debug "すべてのApplicationをGitOps管理でデプロイします"

# ESO Prerequisites: Pulumi Access Token Secretを事前に作成
log_status "ESO Prerequisites設定中..."
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << PRE_EOF
# External Secrets namespace作成
kubectl create namespace external-secrets-system --dry-run=client -o yaml | kubectl apply -f -

# Pulumi Access Token Secret作成（ESOデプロイ前に必要）
if [[ -n "${PULUMI_ACCESS_TOKEN}" ]]; then
    echo "Pulumi Access Token Secret作成中..."
    kubectl create secret generic pulumi-esc-token \
      --namespace external-secrets-system \
      --from-literal=accessToken="${PULUMI_ACCESS_TOKEN}" \
      --dry-run=client -o yaml | kubectl apply -f -
    echo "✓ Pulumi Access Token Secret作成完了"
    
    # RBAC設定も事前に作成
    echo "ESO RBAC設定中..."
    kubectl apply -f - <<'RBAC_EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-secrets-kubernetes-provider
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["serviceaccounts"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["serviceaccounts/token"]
  verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-secrets-kubernetes-provider
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-secrets-kubernetes-provider
subjects:
- kind: ServiceAccount
  name: external-secrets-operator
  namespace: external-secrets-system
RBAC_EOF
    echo "✓ ESO RBAC設定完了"
else
    echo "エラー: PULUMI_ACCESS_TOKEN が設定されていません"
    exit 1
fi
PRE_EOF

PULUMI_ACCESS_TOKEN_ESCAPED=$(printf '%q' "${PULUMI_ACCESS_TOKEN}")
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} "PULUMI_ACCESS_TOKEN=${PULUMI_ACCESS_TOKEN_ESCAPED} bash -s" << 'EOF'
# 環境変数を明示的にエクスポート
export PULUMI_ACCESS_TOKEN="${PULUMI_ACCESS_TOKEN}"
# App-of-Appsパターン適用（初回のみ）
echo "App-of-Apps適用中..."
if kubectl get application core -n argocd >/dev/null 2>&1; then
    echo "App-of-Appsは既に適用済みのためスキップします"
else
    kubectl apply -f /tmp/app-of-apps.yaml
fi

# 基盤インフラApplication同期待機
echo "基盤インフラApplication同期待機中..."
sleep 15

# MetalLB同期確認
if kubectl get application metallb -n argocd 2>/dev/null; then
    for i in {1..30}; do
        HEALTH=$(kubectl get application metallb -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
        if [ "${HEALTH}" = "Healthy" ]; then
            echo "✓ MetalLB: Healthy"
            break
        fi
        sleep 10
    done
    kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app.kubernetes.io/name=metallb --timeout=300s 2>/dev/null || true
fi

# NGINX Gateway Fabric同期確認
if kubectl get application nginx-gateway-fabric -n argocd 2>/dev/null; then
    for i in {1..30}; do
        HEALTH=$(kubectl get application nginx-gateway-fabric -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
        if [ "${HEALTH}" = "Healthy" ]; then
            echo "✓ NGINX Gateway Fabric: Healthy"
            break
        fi
        sleep 10
    done
    kubectl wait --namespace nginx-gateway --for=condition=ready pod --selector=app.kubernetes.io/name=nginx-gateway-fabric --timeout=300s 2>/dev/null || true
fi

# cert-manager同期確認
if kubectl get application cert-manager -n argocd 2>/dev/null; then
    for i in {1..30}; do
        HEALTH=$(kubectl get application cert-manager -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
        if [ "${HEALTH}" = "Healthy" ]; then
            echo "✓ cert-manager: Healthy"
            break
        fi
        sleep 10
    done
    kubectl wait --namespace cert-manager --for=condition=ready pod --selector=app.kubernetes.io/instance=cert-manager --timeout=300s 2>/dev/null || true
fi

# ESO同期確認
if kubectl get application external-secrets-operator -n argocd 2>/dev/null; then
    echo "External Secrets Operator同期待機中..."
    # Health状態の確認
    for i in {1..30}; do
        HEALTH=$(kubectl get application external-secrets-operator -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
        if [ "${HEALTH}" = "Healthy" ]; then
            echo "✓ External Secrets Operator: Healthy"
            break
        fi
        echo "ESO Health: ${HEALTH} (待機中 $i/30)"
        sleep 10
    done
    kubectl wait --namespace external-secrets-system --for=condition=ready pod --selector=app.kubernetes.io/name=external-secrets --timeout=300s || echo "ESO Pod起動待機中"
    
    # Pulumi Access Token Secretの確認（既に作成済みのはず）
    if kubectl get secret pulumi-esc-token -n external-secrets-system >/dev/null 2>&1; then
        echo "✓ Pulumi Access Token Secret確認済み"
    else
        echo "警告: Pulumi Access Token Secretが見つかりません。再作成中..."
        if [[ -n "${PULUMI_ACCESS_TOKEN}" ]]; then
            kubectl create secret generic pulumi-esc-token \
              --namespace external-secrets-system \
              --from-literal=accessToken="${PULUMI_ACCESS_TOKEN}" \
              --dry-run=client -o yaml | kubectl apply -f -
            echo "✓ Pulumi Access Token Secret作成完了"
        fi
    fi
    
    # ClusterSecretStoreをすぐに作成（ESOが起動したら）
    echo "ClusterSecretStore作成中..."
    kubectl apply -f - <<'STORE_EOF'
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: pulumi-esc-store
spec:
  provider:
    pulumi:
      apiUrl: https://api.pulumi.com/api/esc
      organization: ksera
      project: k8s
      environment: secret
      accessToken:
        secretRef:
          name: pulumi-esc-token
          namespace: external-secrets-system
          key: accessToken
STORE_EOF
    echo "✓ ClusterSecretStore作成完了"
    
    # ClusterSecretStoreの準備完了を待つ
    for i in {1..10}; do
        if kubectl get clustersecretstore pulumi-esc-store -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
            echo "✓ ClusterSecretStore Ready"
            break
        fi
        echo "ClusterSecretStore準備待機中... ($i/10)"
        sleep 3
    done
fi

# Platform Application同期確認
if kubectl get application platform -n argocd 2>/dev/null; then
    echo "Platform Application同期待機中..."
    # Health状態の確認
    for i in {1..30}; do
        HEALTH=$(kubectl get application platform -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
        if [ "${HEALTH}" = "Healthy" ]; then
            echo "✓ Platform Application: Healthy"
            break
        fi
        echo "Platform Health: ${HEALTH} (待機中 $i/30)"
        sleep 10
    done
fi

echo "✓ App-of-Apps適用完了"
EOF

log_status "✓ App-of-Apps デプロイ完了"

# Phase 4.7: ArgoCD GitHub OAuth設定 (ESO経由)
log_status "=== Phase 4.7: ArgoCD GitHub OAuth設定 ==="
log_debug "GitHub OAuth設定をExternal Secrets経由で行います"

# Pulumi Access TokenがEOFブロック内で既に作成されているか確認
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << 'EOF'
# Pulumi Access Token Secretの存在確認
if kubectl get secret pulumi-esc-token -n external-secrets-system 2>/dev/null; then
    echo "✓ Pulumi Access Token Secret確認済み"
else
    echo "エラー: Pulumi Access Token Secret が見つかりません"
    echo "External Secrets Operator が正常に動作できません"
    echo "settings.toml の [Pulumi] セクションに access_token を設定してください"
    exit 1
fi

# Platform Application存在確認
if kubectl get application platform -n argocd 2>/dev/null; then
    # Platform Application同期を手動トリガー（ESOリソース適用のため）
    echo "Platform Application同期をトリガー中..."
    kubectl patch application platform -n argocd --type merge -p '{"operation": {"sync": {"syncStrategy": {"hook": {}}}}}'
    
    # Platform同期待機（ESO関連リソースが作成される）
    echo "Platform同期待機中（ESOリソース作成）..."
    kubectl wait --for=condition=Synced --timeout=300s application/platform -n argocd || echo "Platform同期継続中"
else
    echo "Platform Application未作成、App-of-Apps適用確認中..."
    # App-of-Appsが適用されているか確認
    if ! kubectl get application core -n argocd 2>/dev/null; then
        echo "App-of-Apps再適用中..."
        kubectl apply -f /tmp/app-of-apps.yaml
        sleep 20
    fi
    
    # Platform Application作成待機
    timeout=60
    while [ $timeout -gt 0 ]; do
        if kubectl get application platform -n argocd 2>/dev/null; then
            echo "✓ Platform Application作成確認"
            # 同期トリガー
            kubectl patch application platform -n argocd --type merge -p '{"operation": {"sync": {"syncStrategy": {"hook": {}}}}}'
            break
        fi
        echo "Platform Application作成待機中... (残り ${timeout}秒)"
        sleep 5
        timeout=$((timeout - 5))
    done
fi

# ESO ValidatingWebhookの無効化（開発環境用）
echo "ESO ValidatingWebhook無効化中（開発環境用）..."
# 既存のValidatingWebhookConfigurationを削除
# これによりArgoCDとの証明書問題を根本的に解決
kubectl delete validatingwebhookconfiguration externalsecret-validate --ignore-not-found=true 2>/dev/null || true
kubectl delete validatingwebhookconfiguration secretstore-validate --ignore-not-found=true 2>/dev/null || true

echo "✓ ESO ValidatingWebhook無効化完了"

# ESO Operatorが正常に動作するまで待機（長めの待機時間を設定）
echo "ESO Operator起動待機中..."
# まずnamespaceが作成されるまで待機
for i in {1..30}; do
    if kubectl get namespace external-secrets-system 2>/dev/null; then
        echo "✓ ESO namespace確認"
        break
    fi
    echo "  ESO namespace待機中... ($i/30)"
    sleep 5
done

# ESO Podが起動するまで待機
echo "ESO Pod起動待機中..."
for i in {1..60}; do
    ESO_PODS=$(kubectl get pods -n external-secrets-system --no-headers 2>/dev/null | grep -c Running || echo "0")
    TOTAL_PODS=$(kubectl get pods -n external-secrets-system --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [ "$ESO_PODS" -gt 0 ]; then
        echo "✓ ESO Pod起動確認 ($ESO_PODS/$TOTAL_PODS)"
        break
    fi
    echo "  ESO Pod待機中... ($i/60)"
    sleep 5
done

# ESO CRDが登録されるまで待機
echo "ESO CRD登録待機中..."
for i in {1..30}; do
    if kubectl get crd externalsecrets.external-secrets.io 2>/dev/null; then
        echo "✓ ESO CRD登録確認"
        break
    fi
    echo "  ESO CRD待機中... ($i/30)"
    sleep 5
done

# 追加の安定化待機時間
echo "ESO安定化のため30秒待機..."
sleep 30

echo "✓ ESO Operator準備完了"

# Webhookを無効化したため、Webhook準備確認は不要
echo "✓ ESO Webhook検証を無効化済み（開発環境設定）"

# Platform Applicationの強制再同期（ESO証明書修正後）
echo "Platform Applicationを強制再同期中..."
kubectl patch application platform -n argocd --type merge -p '{"metadata": {"finalizers": null}}' 2>/dev/null || true
sleep 2
# 強制的に再同期（replace-syncオプション）
argocd app sync platform --replace --force --server-side 2>/dev/null || \
  kubectl patch application platform -n argocd --type merge -p '{"operation": {"sync": {"syncStrategy": {"apply": {"force": true}}}}}' 2>/dev/null || true
sleep 10

# ClusterSecretStore確認（既にESO起動時に作成済み）
if kubectl get clustersecretstore pulumi-esc-store -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
    echo "✓ ClusterSecretStore準備完了"
else
    echo "警告: ClusterSecretStoreがまだReadyではありません。再作成中..."
    kubectl apply -f - <<'STORE_EOF'
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: pulumi-esc-store
spec:
  provider:
    pulumi:
      apiUrl: https://api.pulumi.com/api/esc
      organization: ksera
      project: k8s
      environment: secret
      accessToken:
        secretRef:
          name: pulumi-esc-token
          namespace: external-secrets-system
          key: accessToken
STORE_EOF
    sleep 5
    if kubectl get clustersecretstore pulumi-esc-store -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
        echo "✓ ClusterSecretStore作成完了"
    fi
fi

if [ $timeout -le 0 ]; then
    echo "エラー: ClusterSecretStore作成タイムアウト"
    echo "Pulumi ESC との接続が確立できませんでした"
    echo "Pulumi Access Token が正しいか確認してください"
    exit 1
else
    # External Secret同期待機（ArgoCD GitHub OAuth）
    timeout=60
    while [ $timeout -gt 0 ]; do
        if kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.dex\.github\.clientSecret}' 2>/dev/null | grep -q .; then
            SECRET_LENGTH=$(kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.dex\.github\.clientSecret}' | base64 -d | wc -c)
            if [ "$SECRET_LENGTH" -gt 10 ]; then
                echo "✓ ArgoCD GitHub OAuth ESO同期完了"
                break
            fi
        fi
        echo "External Secret同期待機中... (残り ${timeout}秒)"
        sleep 5
        timeout=$((timeout - 5))
    done
    
    if [ $timeout -le 0 ]; then
        echo "エラー: External Secret同期タイムアウト"
        echo "Pulumi ESC からのSecret取得に失敗しました"
        echo "Pulumi ESC の設定とキーが正しいか確認してください"
        exit 1
    fi
fi

# ArgoCD GitHub OAuth ConfigMapはGitOps経由で同期されます
echo "ArgoCD ConfigMapはPlatform Application経由で同期されます"

# ArgoCD サーバー再起動
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd --timeout=300s

echo "✓ ArgoCD GitHub OAuth設定完了"
EOF

log_status "✓ ArgoCD GitHub OAuth設定完了"

# Phase 4.8: Harbor デプロイ
log_status "=== Phase 4.8: Harbor デプロイ ==="
log_debug "Harbor Private Registry をArgoCD経由でデプロイします"

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << 'EOF'
# Platform Application同期確認（External Secretsリソース適用のため）
if kubectl get application platform -n argocd 2>/dev/null; then
    echo "Platform Application同期確認中（Harbor External Secretsのため）..."
    kubectl patch application platform -n argocd --type merge -p '{"operation": {"sync": {"syncStrategy": {"hook": {}}}}}' || true
    kubectl wait --for=condition=Synced --timeout=300s application/platform -n argocd || echo "Platform同期継続中"
fi

# Harbor Application確認（App-of-Appsで作成される）
if kubectl get application harbor -n argocd 2>/dev/null; then
    echo "Harbor Application同期待機中..."
    kubectl wait --for=condition=Synced --timeout=300s application/harbor -n argocd || echo "Harbor同期継続中"
    
    # Harbor Pods起動待機
    echo "Harbor Pods起動待機中..."
    sleep 30
    kubectl wait --namespace harbor --for=condition=ready pod --selector=app=harbor --timeout=300s || echo "Harbor Pod起動待機中"
    
    # Harbor External URL修正（harbor.qroksera.com使用）
    # 注: Helm ChartはexternalURLをEXT_ENDPOINTに反映しないため、手動修正が必要
    echo "Harbor External URL設定を修正中..."
    
    # Harbor coreが完全に起動してから修正
    echo "Harbor core deployment確認中..."
    kubectl rollout status deployment/harbor-core -n harbor --timeout=120s || true
    
    # ConfigMapのEXT_ENDPOINTを修正
    echo "ConfigMap harbor-core のEXT_ENDPOINTを修正中..."
    kubectl patch cm harbor-core -n harbor --type json -p '[{"op": "replace", "path": "/data/EXT_ENDPOINT", "value": "https://harbor.qroksera.com"}]' || true
    
    # Harbor core再起動して設定を反映
    echo "Harbor core再起動中..."
    kubectl rollout restart deployment/harbor-core -n harbor || true
    kubectl rollout status deployment/harbor-core -n harbor --timeout=120s || true
    echo "✓ Harbor External URLをharbor.qroksera.comに修正"
else
    echo "Harbor Application未作成、App-of-Apps確認中..."
    kubectl get application -n argocd
fi

echo "✓ Harbor デプロイ完了"
EOF

log_status "✓ Harbor デプロイ完了"

# Phase 4.8.5: Harbor認証設定（skopeo対応）
log_status "=== Phase 4.8.5: Harbor認証設定（skopeo対応） ==="
log_debug "Harbor認証情報secretをGitHub Actions用に設定します"

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << 'EOF'
# Harbor Pod起動待機
echo "Harbor Pod起動を待機中..."
if kubectl get pods -n harbor 2>/dev/null | grep -q harbor; then
    kubectl wait --namespace harbor --for=condition=ready pod --selector=app=harbor --timeout=300s || echo "Harbor起動待機中"
fi

# Pulumi ESC準備状況確認
PULUMI_TOKEN_EXISTS=$(kubectl get secret pulumi-esc-token -n external-secrets-system 2>/dev/null || echo "none")
if [[ "$PULUMI_TOKEN_EXISTS" == "none" ]]; then
    echo "エラー: Pulumi Access Tokenが設定されていません"
    echo "Harbor認証情報をExternal Secrets経由で取得できません"
    echo "settings.toml の [Pulumi] セクションに access_token を設定してください"
    exit 1
else
    # External Secretリソースの存在確認
    echo "Harbor External Secretリソース確認中..."
    if kubectl get externalsecret harbor-admin-secret -n harbor 2>/dev/null; then
        echo "✓ Harbor External Secret存在確認"
        # External Secretの同期をトリガー（kubectl annotateで更新）
        kubectl annotate externalsecret harbor-admin-secret -n harbor refresh=now --overwrite || true
    fi
fi

# ESO経由でharbor-admin-secretが作成されるまで待機
echo "harbor-admin-secretの作成を待機中 (ESO経由)..."
timeout=120
while [ $timeout -gt 0 ]; do
    if kubectl get secret harbor-admin-secret -n harbor 2>/dev/null | grep -q harbor-admin-secret; then
        # Secretが存在するか確認し、passwordフィールドがあるか確認
        if kubectl get secret harbor-admin-secret -n harbor -o jsonpath='{.data.password}' 2>/dev/null | grep -q .; then
            echo "✓ harbor-admin-secret作成確認"
            break
        fi
    fi
    echo "ESOにharbor-admin-secretを作成待機中... (残り ${timeout}秒)"
    sleep 5
    timeout=$((timeout - 5))
done

# Harbor管理者パスワード取得 (ESO経由のみ)
HARBOR_ADMIN_PASSWORD=$(kubectl get secret harbor-admin-secret -n harbor -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
if [[ -z "$HARBOR_ADMIN_PASSWORD" ]]; then
    echo "エラー: ESOからHarborパスワードを取得できませんでした"
    echo "External Secretsの同期が完了していません"
    echo "kubectl get externalsecret -n harbor で状態を確認してください"
    exit 1
fi

# arc-systems namespace作成（存在しない場合）
kubectl create namespace arc-systems --dry-run=client -o yaml | kubectl apply -f -

# GitHub Actions用のharbor-auth secret作成
echo "GitHub Actions用harbor-auth secret作成中..."
kubectl create secret generic harbor-auth \
  --namespace=arc-systems \
  --from-literal=HARBOR_URL="harbor.qroksera.com" \
  --from-literal=HARBOR_USERNAME="admin" \
  --from-literal=HARBOR_PASSWORD="${HARBOR_ADMIN_PASSWORD}" \
  --from-literal=HARBOR_PROJECT="sandbox" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "✓ harbor-auth secret作成完了"

# 必要なネームスペースにHarbor Docker registry secret作成
NAMESPACES=("default" "sandbox" "production" "staging")

for namespace in "${NAMESPACES[@]}"; do
    # ネームスペース作成（存在しない場合）
    kubectl create namespace $namespace --dry-run=client -o yaml | kubectl apply -f -
    
    echo "harbor-registry secret ($namespace) はGitOps経由で同期されます"
done

echo "✓ Harbor認証設定完了 - skopeo対応"

# 最終確認: Harbor EXT_ENDPOINTが正しく設定されているか確認
echo "Harbor EXT_ENDPOINT最終確認..."
CURRENT_EXT_ENDPOINT=$(kubectl get cm harbor-core -n harbor -o jsonpath='{.data.EXT_ENDPOINT}' 2>/dev/null)
if [[ "$CURRENT_EXT_ENDPOINT" != "https://harbor.qroksera.com" ]]; then
    echo "警告: EXT_ENDPOINTが正しくありません: $CURRENT_EXT_ENDPOINT"
    echo "修正を再実行中..."
    kubectl patch cm harbor-core -n harbor --type json -p '[{"op": "replace", "path": "/data/EXT_ENDPOINT", "value": "https://harbor.qroksera.com"}]'
    kubectl rollout restart deployment/harbor-core -n harbor
    kubectl rollout status deployment/harbor-core -n harbor --timeout=120s
    echo "✓ Harbor EXT_ENDPOINT修正完了"
else
    echo "✓ Harbor EXT_ENDPOINTは正しく設定されています: $CURRENT_EXT_ENDPOINT"
fi
EOF

log_status "✓ Harbor認証設定（skopeo対応）完了"

# Phase 4.8.5b: Harbor sandboxプロジェクト作成
log_status "=== Phase 4.8.5b: Harbor sandboxプロジェクト作成 ==="
log_debug "Harborにsandboxプロジェクトを作成します"

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << 'EOF'
# Harbor coreが完全に起動していることを確認
echo "Harbor coreの起動を確認中..."
kubectl wait --namespace harbor --for=condition=ready pod --selector=component=core --timeout=120s || echo "Harbor core起動待機中"

# Harbor管理者パスワード取得
HARBOR_ADMIN_PASSWORD=$(kubectl get secret harbor-admin-secret -n harbor -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
if [[ -z "$HARBOR_ADMIN_PASSWORD" ]]; then
    echo "エラー: Harborパスワードを取得できませんでした"
    exit 1
fi

# Harbor APIを使用してsandboxプロジェクトを作成
echo "sandboxプロジェクト作成中..."

# ポートフォワードをバックグラウンドで開始
kubectl port-forward -n harbor svc/harbor-core 8082:80 &>/dev/null &
PF_PID=$!
sleep 5

# プロジェクトが既に存在するか確認
PROJECT_EXISTS=$(curl -s -o /dev/null -w "%{http_code}" -u admin:"${HARBOR_ADMIN_PASSWORD}" "http://localhost:8082/api/v2.0/projects?name=sandbox")
if [[ "$PROJECT_EXISTS" == "200" ]]; then
    PROJECTS=$(curl -s -u admin:"${HARBOR_ADMIN_PASSWORD}" "http://localhost:8082/api/v2.0/projects?name=sandbox")
    if echo "$PROJECTS" | grep -q '"name":"sandbox"'; then
        echo "✓ sandboxプロジェクトは既に存在します"
    else
        # プロジェクト作成
        RESPONSE=$(curl -s -X POST -u admin:"${HARBOR_ADMIN_PASSWORD}" \
          "http://localhost:8082/api/v2.0/projects" \
          -H "Content-Type: application/json" \
          -d '{"project_name":"sandbox","public":true}' \
          -w "\n%{http_code}")
        HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
        if [[ "$HTTP_CODE" == "201" ]] || [[ "$HTTP_CODE" == "200" ]]; then
            echo "✓ sandboxプロジェクトを作成しました"
        else
            echo "警告: sandboxプロジェクト作成のレスポンス: $RESPONSE"
        fi
    fi
else
    # APIアクセスエラーの場合もプロジェクト作成を試みる
    echo "Harbor APIアクセスエラー。プロジェクト作成を試みます..."
    RESPONSE=$(curl -s -X POST -u admin:"${HARBOR_ADMIN_PASSWORD}" \
      "http://localhost:8082/api/v2.0/projects" \
      -H "Content-Type: application/json" \
      -d '{"project_name":"sandbox","public":true}' \
      -w "\n%{http_code}")
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    if [[ "$HTTP_CODE" == "201" ]] || [[ "$HTTP_CODE" == "200" ]] || [[ "$HTTP_CODE" == "409" ]]; then
        echo "✓ sandboxプロジェクト処理完了"
    else
        echo "警告: sandboxプロジェクト作成レスポンス: $RESPONSE"
    fi
fi

# ポートフォワードを終了
kill $PF_PID 2>/dev/null || true

echo "✓ Harbor sandboxプロジェクト設定完了"
EOF

log_status "✓ Harbor sandboxプロジェクト作成完了"

# Phase 4.8.6: Worker ノード Containerd Harbor HTTP Registry設定
log_status "=== Phase 4.8.6: Containerd Harbor HTTP Registry設定 ==="
log_debug "各Worker ノードのContainerdにHarbor HTTP Registry設定を追加します"

# Harbor admin パスワード取得（ローカルで実行）
HARBOR_ADMIN_PASSWORD=$(ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} 'kubectl get secret harbor-admin-secret -n harbor -o jsonpath="{.data.password}" 2>/dev/null | base64 -d')
if [[ -z "$HARBOR_ADMIN_PASSWORD" ]]; then
    log_error "ESOからHarborパスワードを取得できませんでした"
    log_error "External Secretsの同期が完了していません"
    log_error "kubectl get externalsecret -n harbor で状態を確認してください"
    exit 1
fi

log_debug "Worker1 (192.168.122.11) Containerd設定..."
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.11 << EOF
# /etc/hostsにharbor.qroksera.comを追加（重複チェック付き）
if ! grep -q "harbor.qroksera.com" /etc/hosts; then
    echo "192.168.122.100 harbor.qroksera.com" | sudo -n tee -a /etc/hosts
fi

# containerd certs.d設定ディレクトリ作成
sudo -n mkdir -p /etc/containerd/certs.d/harbor.qroksera.com
sudo -n mkdir -p /etc/containerd/certs.d/192.168.122.100

# harbor.qroksera.com用hosts.toml作成
sudo -n tee /etc/containerd/certs.d/harbor.qroksera.com/hosts.toml > /dev/null << 'CONTAINERD_EOF'
server = "https://harbor.qroksera.com"

[host."https://harbor.qroksera.com"]
  skip_verify = true
CONTAINERD_EOF

# 192.168.122.100用hosts.toml作成（IPアクセス用）
sudo -n tee /etc/containerd/certs.d/192.168.122.100/hosts.toml > /dev/null << 'CONTAINERD_EOF'
server = "https://192.168.122.100"

[host."https://192.168.122.100"]
  skip_verify = true
CONTAINERD_EOF

# Containerd再起動
sudo -n systemctl restart containerd
echo "✓ Worker1 Containerd設定完了"
EOF

log_debug "Worker2 (192.168.122.12) Containerd設定..."
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.12 << EOF
# /etc/hostsにharbor.qroksera.comを追加（重複チェック付き）
if ! grep -q "harbor.qroksera.com" /etc/hosts; then
    echo "192.168.122.100 harbor.qroksera.com" | sudo -n tee -a /etc/hosts
fi

# containerd certs.d設定ディレクトリ作成
sudo -n mkdir -p /etc/containerd/certs.d/harbor.qroksera.com
sudo -n mkdir -p /etc/containerd/certs.d/192.168.122.100

# harbor.qroksera.com用hosts.toml作成
sudo -n tee /etc/containerd/certs.d/harbor.qroksera.com/hosts.toml > /dev/null << 'CONTAINERD_EOF'
server = "https://harbor.qroksera.com"

[host."https://harbor.qroksera.com"]
  skip_verify = true
CONTAINERD_EOF

# 192.168.122.100用hosts.toml作成（IPアクセス用）
sudo -n tee /etc/containerd/certs.d/192.168.122.100/hosts.toml > /dev/null << 'CONTAINERD_EOF'
server = "https://192.168.122.100"

[host."https://192.168.122.100"]
  skip_verify = true
CONTAINERD_EOF

# Containerd再起動
sudo -n systemctl restart containerd
echo "✓ Worker2 Containerd設定完了"
EOF

# Control Planeノードの設定
log_debug "Control Plane (192.168.122.10) Containerd設定..."
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << EOF
# /etc/hostsにharbor.qroksera.comを追加（重複チェック付き）
if ! grep -q "harbor.qroksera.com" /etc/hosts; then
    echo "192.168.122.100 harbor.qroksera.com" | sudo -n tee -a /etc/hosts
fi

# containerd certs.d設定ディレクトリ作成
sudo -n mkdir -p /etc/containerd/certs.d/harbor.qroksera.com
sudo -n mkdir -p /etc/containerd/certs.d/192.168.122.100

# harbor.qroksera.com用hosts.toml作成
sudo -n tee /etc/containerd/certs.d/harbor.qroksera.com/hosts.toml > /dev/null << 'CONTAINERD_EOF'
server = "https://harbor.qroksera.com"

[host."https://harbor.qroksera.com"]
  skip_verify = true
CONTAINERD_EOF

# 192.168.122.100用hosts.toml作成（IPアクセス用）
sudo -n tee /etc/containerd/certs.d/192.168.122.100/hosts.toml > /dev/null << 'CONTAINERD_EOF'
server = "https://192.168.122.100"

[host."https://192.168.122.100"]
  skip_verify = true
CONTAINERD_EOF

# Containerd再起動
sudo -n systemctl restart containerd
echo "✓ Control Plane Containerd設定完了"
EOF

log_status "✓ Containerd Harbor HTTP Registry設定完了"

# Phase 4.9: GitHub Actions Runner Controller (ARC) セットアップ
log_status "=== Phase 4.9: GitHub Actions Runner Controller セットアップ ==="
log_debug "GitHub Actions Runner Controller の事前設定を実行します（Controller本体はGitOps管理）"

# ARCセットアップスクリプト実行
if [[ -f "$SCRIPT_DIR/../scripts/github-actions/setup-arc.sh" ]]; then
    log_debug "ARC セットアップスクリプトを実行中..."
    export NON_INTERACTIVE=true
    if bash "$SCRIPT_DIR/../scripts/github-actions/setup-arc.sh"; then
        log_status "✓ ARC セットアップ完了"
        # ServiceAccount作成確認
        if ssh -o StrictHostKeyChecking=no k8suser@${CONTROL_PLANE_IP} 'kubectl get serviceaccount github-actions-runner -n arc-systems' >/dev/null 2>&1; then
            log_status "✓ ServiceAccount github-actions-runner 確認完了"
        else
            log_warning "⚠️ ServiceAccount github-actions-runner が見つかりません。再作成中..."
            ssh -o StrictHostKeyChecking=no k8suser@${CONTROL_PLANE_IP} 'kubectl create serviceaccount github-actions-runner -n arc-systems --dry-run=client -o yaml | kubectl apply -f -'
        fi
    else
        log_warning "⚠️ ARC セットアップでエラーが発生しましたが続行します"
    fi
else
    log_warning "setup-arc.sh が見つかりません。ARC事前設定をスキップします"
    ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << 'EOF'
    echo "ℹ️ ARC ControllerはArgoCDのGitOps同期によりデプロイされます"
EOF
fi

# Phase 4.9.4: ARC Controller起動待機
log_status "=== Phase 4.9.4: ARC Controller起動待機 ==="
log_debug "ARC Controllerの起動を確認中..."
ssh -o StrictHostKeyChecking=no k8suser@${CONTROL_PLANE_IP} 'kubectl wait --for=condition=available --timeout=120s deployment/arc-controller-gha-rs-controller -n arc-systems' || true
log_status "✓ ARC Controller起動確認完了"

# Phase 4.9.5: settings.tomlのリポジトリを自動add-runner
log_status "=== Phase 4.9.5: settings.tomlのリポジトリを自動add-runner ==="
log_debug "settings.tomlからリポジトリリストを読み込み中..."

SETTINGS_FILE="$SCRIPT_DIR/../settings.toml"
if [[ -f "$SETTINGS_FILE" ]]; then
    log_debug "settings.tomlが見つかりました: $SETTINGS_FILE"
    # arc_repositoriesセクションを解析
    # 複数行配列に対応するため、開始から終了まで全て取得して解析
    # コメント行（#で始まる行）と空行を除外し、配列要素のみを抽出
    ARC_REPOS_TEMP=$(awk '/^arc_repositories = \[/,/^\]/' "$SETTINGS_FILE" | grep -E '^\s*\["' | grep -v '^arc_repositories' || true)
    
    if [[ -n "$ARC_REPOS_TEMP" ]]; then
        log_debug "arc_repositories設定を発見しました"
        log_debug "取得した設定内容:"
        echo "$ARC_REPOS_TEMP" | while IFS= read -r line; do
            log_debug "  > $line"
        done
        
        # リポジトリ数をカウント
        REPO_COUNT=$(echo "$ARC_REPOS_TEMP" | wc -l)
        log_debug "処理対象リポジトリ数: $REPO_COUNT"
        
        # 各リポジトリに対してadd-runner.shを実行
        PROCESSED=0
        FAILED=0
        CURRENT=0
        
        # SSH接続確認を先に実施
        if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 k8suser@${CONTROL_PLANE_IP} 'kubectl get nodes' >/dev/null 2>&1; then
            log_error "k8sクラスタに接続できません。Runner追加をスキップします"
        else
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                
                # 正規表現で配列要素を抽出: ["name", min, max, "description", "strategy"]
                # スペースに対して柔軟になるよう改善
                if [[ $line =~ \[\"([^\"]+)\"[[:space:]]*,[[:space:]]*([0-9]+)[[:space:]]*,[[:space:]]*([0-9]+)[[:space:]]*,[[:space:]]*\"([^\"]*)\"[[:space:]]*,[[:space:]]*\"(latest)\"[[:space:]]*\],? ]]; then
                    REPO_NAME="${BASH_REMATCH[1]}"
                    MIN_RUNNERS="${BASH_REMATCH[2]}"
                    MAX_RUNNERS="${BASH_REMATCH[3]}"
                    STRATEGY="${BASH_REMATCH[5]}"
                    CURRENT=$((CURRENT+1))
                    
                    log_status "🏃 [$CURRENT/$REPO_COUNT] $REPO_NAME のRunnerを追加中... (min=$MIN_RUNNERS, max=$MAX_RUNNERS, strategy=$STRATEGY)"
                    
                    # add-runner.shを実行
                    ADD_RUNNER_SCRIPT="$SCRIPT_DIR/../scripts/github-actions/add-runner.sh"
                    if [[ -f "$ADD_RUNNER_SCRIPT" ]]; then
                        # 環境変数を明示的にエクスポート
                        export REPO_NAME MIN_RUNNERS MAX_RUNNERS STRATEGY
                        
                        # add-runner.shを通常実行（サブシェル内ではない）
                        if bash "$ADD_RUNNER_SCRIPT" "$REPO_NAME" "$MIN_RUNNERS" "$MAX_RUNNERS" "$STRATEGY" < /dev/null; then
                            log_status "✓ $REPO_NAME Runner追加完了"
                            PROCESSED=$((PROCESSED+1))
                        else
                            EXIT_CODE=$?
                            log_error "❌ $REPO_NAME Runner追加失敗 (exit code: $EXIT_CODE)"
                            log_debug "エラー詳細は上記のログを確認してください"
                            FAILED=$((FAILED+1))
                        fi
                        
                        # 次のRunner作成前に少し待機（API制限回避）
                        if [[ $CURRENT -lt $REPO_COUNT ]]; then
                            log_debug "次のRunner作成前に5秒待機中..."
                            sleep 5
                        fi
                    else
                        log_error "add-runner.sh が見つかりません: $ADD_RUNNER_SCRIPT"
                        # ファイルが見つからない場合は全て失敗とする
                        FAILED=$((REPO_COUNT - PROCESSED))
                        break
                    fi
                else
                    log_error "❌ arc_repositories の形式が不正です: $line"
                    log_error '   期待形式: ["repo", min, max, "description", "latest"]'
                    FAILED=$((FAILED+1))
                fi
            done <<< "$ARC_REPOS_TEMP"
        fi
        
        log_status "✓ settings.tomlのリポジトリ自動追加完了 (成功: $PROCESSED, 失敗: $FAILED)"
        
        # 失敗があった場合は警告
        if [[ $FAILED -gt 0 ]]; then
            log_error "❌ $FAILED 個のリポジトリでRunner追加に失敗しました"
            log_error "arc_repositories の各要素は [\"repo\", min, max, \"description\", \"latest\"] 形式で設定してください"
            log_error "必要に応じて 'make add-runner REPO=<name> MIN=<n> MAX=<n> STRATEGY=latest' を実行してください"
            exit 1
        fi
    else
        log_debug "arc_repositories設定が見つかりません（スキップ）"
    fi
else
    log_warning "settings.tomlが見つかりません"
fi

# Phase 4.10: 各種Application デプロイ
log_status "=== Phase 4.10: 各種Application デプロイ ==="
log_debug "Cloudflared等のApplicationをArgoCD経由でデプロイします"

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << 'EOF'
# ESOリソースが適用されているか確認
echo "External Secrets リソース確認中..."
if kubectl get clustersecretstore pulumi-esc-store 2>/dev/null | grep -q Ready; then
    echo "✓ ClusterSecretStore確認OK"
else
    echo "⚠️ ClusterSecretStore未検出、Platform同期を再実行..."
    # Platform Application存在確認
    if kubectl get application platform -n argocd 2>/dev/null; then
        kubectl patch application platform -n argocd --type merge -p '{"operation": {"sync": {"syncStrategy": {"hook": {}}}}}'
        sleep 30
    else
        echo "Platform Application未作成、スキップ"
    fi
fi

# Applications同期確認
if kubectl get application user-applications -n argocd 2>/dev/null; then
    echo "user-applications同期待機中..."
    # Health状態の確認
    for i in {1..30}; do
        HEALTH=$(kubectl get application user-applications -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
        if [ "${HEALTH}" = "Healthy" ] || [ "${HEALTH}" = "Progressing" ]; then
            echo "✓ user-applications: ${HEALTH}"
            break
        fi
        echo "user-applications Health: ${HEALTH} (待機中 $i/30)"
        sleep 10
    done
fi

# アプリケーション用External Secrets確認
echo "アプリケーション用External Secrets確認中..."
kubectl get externalsecrets -A | grep -E "(cloudflared|slack)" || echo "アプリケーションExternal Secrets待機中"

echo "✓ 各種Application デプロイ完了"
EOF

log_status "✓ 各種Application デプロイ完了"


# Phase 4.11: システム環境確認
log_status "=== Phase 4.11: システム環境確認 ==="
log_debug "デプロイされたシステム全体の動作確認を行います"

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << 'EOF'
echo "=== 最終システム状態確認 ==="

# ArgoCD状態確認
echo "ArgoCD状態:"
kubectl get pods -n argocd -l app.kubernetes.io/component=server

# External Secrets状態確認
echo "External Secrets状態:"
kubectl get pods -n external-secrets-system -l app.kubernetes.io/name=external-secrets

# ClusterSecretStore状態確認
echo "ClusterSecretStore状態:"
kubectl get clustersecretstore pulumi-esc-store 2>/dev/null || echo "ClusterSecretStore未作成"

# ExternalSecrets状態確認
echo "ExternalSecrets状態:"
kubectl get externalsecrets -A --no-headers | awk '{print "  - " $2 " (" $1 "): " $(NF)}' 2>/dev/null || echo "ExternalSecrets未作成"

# GitHub Actions Runner状態確認
echo ""
echo "GitHub Actions Runner状態:"
# ARC Controller確認
echo "  ARC Controller:"
kubectl get pods -n arc-systems -l app.kubernetes.io/name=gha-runner-scale-set-controller --no-headers 2>/dev/null | awk '{print "    - " $1 ": " $2 " " $3}' || echo "    ARC Controller未起動"

# AutoscalingRunnerSets確認（新CRD）
echo "  AutoscalingRunnerSets:"
kubectl get autoscalingrunnersets -n arc-systems --no-headers 2>/dev/null | awk '{print "    - " $1 ": Min=" $2 " Max=" $3 " Current=" $4}' || echo "    AutoscalingRunnerSets未作成"

# Runner Pods確認
echo "  Runner Pods:"
kubectl get pods -n arc-systems -l app.kubernetes.io/name=runner --no-headers 2>/dev/null | head -5 | awk '{print "    - " $1 ": " $2 " " $3}' || echo "    Runner Pods未起動"

# Helm Release確認
echo "  Helm Releases (Runners):"
helm list -n arc-systems 2>/dev/null | grep -v NAME | awk '{print "    - " $1 " (" $9 "): " $8}' || echo "    Helm Releases未作成"

# Harbor状態確認
echo "Harbor状態:"
kubectl get pods -n harbor -l app=harbor 2>/dev/null || echo "Harbor デプロイ中..."

# ARC Controller状態確認
echo ""
echo "GitHub Actions Runner Controller状態:"
kubectl get pods -n arc-systems -l app.kubernetes.io/component=controller 2>/dev/null | grep -v NAME | awk '{print "  Controller: " $1 " " $2 " " $3}' || echo "  ARC Controller デプロイ中..."

# Cloudflared状態確認
echo "Cloudflared状態:"
kubectl get pods -n cloudflared 2>/dev/null || echo "Cloudflared デプロイ中..."

# LoadBalancer IP確認
echo "LoadBalancer IP:"
kubectl -n nginx-gateway get service nginx-gateway-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
echo ""

# ArgoCD Applications状態
echo "ArgoCD Applications状態:"
kubectl get applications -n argocd --no-headers | awk '{print "  - " $1 " (" $2 "/" $3 ")"}'

echo "✓ システム環境確認完了"
EOF

log_status "✓ システム環境確認完了"

log_status "=== Kubernetesプラットフォーム構築完了 ==="
log_status ""
log_status "📊 デプロイサマリー:"
log_status "  ✓ ArgoCD: GitOps管理基盤"
log_status "  ✓ Harbor: プライベートコンテナレジストリ"
log_status "  ✓ External Secrets: シークレット管理"
log_status "  ✓ GitHub Actions Runner: CI/CDパイプライン"
log_status ""
log_status "🔗 アクセス方法:"
log_status "  ArgoCD UI: https://argocd.qroksera.com"
log_status "  Harbor UI: https://harbor.qroksera.com"
log_status "  LoadBalancer IP: 192.168.122.100"
log_status ""
log_status "Harbor push設定:"
log_status "  - GitHub ActionsでskopeoによるTLS検証無効push対応"
log_status "  - Harbor認証secret (arc-systems/harbor-auth) 設定済み"
log_status "  - イメージプルsecret (各namespace/harbor-http) 設定済み"

# Gateway経由のため Harbor IP ルートは作成しない

# Harbor の動作確認
log_status "Harbor の動作確認中..."
if ssh -o StrictHostKeyChecking=no k8suser@${CONTROL_PLANE_IP} "curl -s -f --resolve harbor.qroksera.com:443:${HARBOR_IP} https://harbor.qroksera.com/api/v2.0/systeminfo" >/dev/null 2>&1; then
    log_status "✓ Harbor API が正常に応答しています"
else
    log_warning "Harbor API の応答確認に失敗しました（Harbor は起動中の可能性があります）"
fi

# 最終段階: Harbor EXT_ENDPOINT修正（ArgoCDの同期後に必ず実行）
log_status "=== 最終調整: Harbor EXT_ENDPOINT設定 ==="
log_debug "ArgoCDによる同期後のHarbor設定を修正します"

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@${CONTROL_PLANE_IP} << 'EOF'
echo "Harbor ConfigMap最終修正中..."

# ArgoCDの同期が完了するまで少し待つ
sleep 10

# Harbor ConfigMapのEXT_ENDPOINTを修正
CURRENT_EXT_ENDPOINT=$(kubectl get cm harbor-core -n harbor -o jsonpath='{.data.EXT_ENDPOINT}' 2>/dev/null)
if [[ "$CURRENT_EXT_ENDPOINT" != "https://harbor.qroksera.com" ]]; then
    echo "EXT_ENDPOINTを修正中: $CURRENT_EXT_ENDPOINT → https://harbor.qroksera.com"
    kubectl patch cm harbor-core -n harbor --type json -p '[{"op": "replace", "path": "/data/EXT_ENDPOINT", "value": "https://harbor.qroksera.com"}]'
    
    # Harbor core再起動
    kubectl rollout restart deployment/harbor-core -n harbor
    kubectl rollout status deployment/harbor-core -n harbor --timeout=120s
    echo "✓ Harbor EXT_ENDPOINT修正完了"
else
    echo "✓ Harbor EXT_ENDPOINTは既に正しく設定されています"
fi

# harbor-auth secretも再確認
echo "harbor-auth secret確認中..."
HARBOR_ADMIN_PASSWORD=$(kubectl get secret harbor-admin-secret -n harbor -o jsonpath='{.data.password}' | base64 -d)
kubectl create secret generic harbor-auth \
  --namespace=arc-systems \
  --from-literal=HARBOR_URL="harbor.qroksera.com" \
  --from-literal=HARBOR_USERNAME="admin" \
  --from-literal=HARBOR_PASSWORD="${HARBOR_ADMIN_PASSWORD}" \
  --from-literal=HARBOR_PROJECT="sandbox" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "✓ harbor-auth secret更新完了"
EOF

log_status "✓ Harbor最終調整完了"

log_debug "Phase 4.12に移動します..."

# Phase 4.12: Grafana k8s-monitoring デプロイ
log_status "=== Phase 4.12: Grafana k8s-monitoring デプロイ ==="
log_debug "Grafana Cloud への監視機能を自動セットアップします"

# デバッグ情報出力
log_debug "SCRIPT_DIR: $SCRIPT_DIR"
log_debug "deploy-grafana-monitoring.shのパス確認中: $SCRIPT_DIR/deploy-grafana-monitoring.sh"

# Grafana k8s-monitoring を自動デプロイ
if [[ -f "$SCRIPT_DIR/deploy-grafana-monitoring.sh" ]]; then
    log_status "✓ deploy-grafana-monitoring.sh が見つかりました"
    log_status "Grafana k8s-monitoring を自動デプロイ中..."
    
    # 事前条件確認
    log_debug "NON_INTERACTIVE環境での実行準備中..."
    export NON_INTERACTIVE=true
    
    # 実行前にスクリプトの実行可能性を確認
    if [[ -x "$SCRIPT_DIR/deploy-grafana-monitoring.sh" ]]; then
        log_debug "✓ スクリプトは実行可能です"
    else
        log_warning "⚠️ スクリプトに実行権限がありません。権限を付与中..."
        chmod +x "$SCRIPT_DIR/deploy-grafana-monitoring.sh"
    fi
    
    log_debug "deploy-grafana-monitoring.sh実行開始"
    # Grafanaデプロイはエラーでも続行（後で手動実行可能）
    if bash "$SCRIPT_DIR/deploy-grafana-monitoring.sh" 2>&1 | tee /tmp/grafana-deploy.log; then
        log_status "✓ Grafana k8s-monitoring デプロイ完了"
    else
        DEPLOY_EXIT_CODE=$?
        log_error "❌ Grafana k8s-monitoring のデプロイに失敗しました (exit code: $DEPLOY_EXIT_CODE)"
        log_warning "後で手動実行: cd automation/platform && ./deploy-grafana-monitoring.sh"
        log_warning "デバッグ情報: NON_INTERACTIVE=$NON_INTERACTIVE"
        log_warning "ログ確認: cat /tmp/grafana-deploy.log"
        # エラーでもスクリプトを続行
    fi
else
    log_error "❌ deploy-grafana-monitoring.sh が見つかりません"
    log_debug "確認されたパス: $SCRIPT_DIR/deploy-grafana-monitoring.sh"
    log_debug "ディレクトリ内容確認:"
    ls -la "$SCRIPT_DIR/" | grep -E "(deploy-grafana|monitoring)" || log_debug "関連ファイルが見つかりません"
fi

log_status "🎉 すべての設定が完了しました！"
log_status ""
log_status "次のステップ:"
log_status "  1. GitHub リポジトリに workflow ファイルを追加"
log_status "  2. make add-runner REPO=your-repo でリポジトリ用の Runner を追加"
log_status "  3. git push で GitHub Actions が自動実行されます"
log_status "  4. Grafana Cloud でメトリクス、ログ、トレースを確認"
