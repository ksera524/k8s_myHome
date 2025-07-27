#!/bin/bash

# External Secrets を使用したHarbor認証情報デプロイスクリプト
# automation/platform/create-harbor-secrets.sh の代替実装

set -euo pipefail

# カラー設定
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

print_status "=== External Secrets による Harbor 認証情報デプロイ ==="

# 前提条件確認
print_status "前提条件を確認中..."

# External Secrets Operator が稼働中かチェック
ESO_DEPLOYMENTS=$(kubectl get deployments -n external-secrets-system --no-headers 2>/dev/null | grep -E "(external-secrets)" | wc -l || echo "0")
if [ "$ESO_DEPLOYMENTS" = "0" ]; then
    print_error "External Secrets Operator が見つかりません"
    print_error "先に setup-external-secrets.sh を実行してください"
    exit 1
fi

print_debug "✓ External Secrets Operator 稼働確認完了"

# Pulumi Access Token が設定済みかチェック
if ! kubectl get secret pulumi-access-token -n external-secrets-system >/dev/null 2>&1; then
    print_error "Pulumi Access Token が設定されていません"
    print_error "以下のいずれかの方法で設定してください："
    print_error "1. ./setup-pulumi-pat.sh --interactive"
    print_error "2. export PULUMI_ACCESS_TOKEN=\"pul-xxx...\" && echo \"\$PULUMI_ACCESS_TOKEN\" | ./setup-pulumi-pat.sh"
    exit 1
fi

print_debug "✓ Pulumi Access Token 設定確認完了"

# ClusterSecretStore が設定済みかチェック
if ! kubectl get clustersecretstore pulumi-esc-store >/dev/null 2>&1; then
    print_warning "ClusterSecretStore 'pulumi-esc-store' が見つかりません"
    print_debug "ArgoCD経由でのClusterSecretStore作成を待機中..."
    
    # ArgoCD Application が存在するかチェック
    if kubectl get application external-secrets-config -n argocd >/dev/null 2>&1; then
        # ArgoCD同期を促進
        print_debug "ArgoCD external-secrets-config同期を促進中..."
        kubectl patch application external-secrets-config -n argocd -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type=merge 2>/dev/null || true
        
        # ClusterSecretStore作成待機
        timeout=120
        while [ $timeout -gt 0 ]; do
            if kubectl get clustersecretstore pulumi-esc-store >/dev/null 2>&1; then
                print_status "✓ ClusterSecretStore が作成されました"
                break
            fi
            echo "ClusterSecretStore作成待機中... (残り ${timeout}秒)"
            sleep 10
            timeout=$((timeout - 10))
        done
        
        if [ $timeout -le 0 ]; then
            print_warning "ClusterSecretStore作成がタイムアウトしました"
            print_debug "手動でClusterSecretStoreを作成します..."
            # フォールバック: 手動作成
            cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: pulumi-esc-store
spec:
  provider:
    pulumi:
      organization: ksera
      project: k8s
      environment: secret
      accessToken:
        secretRef:
          name: pulumi-access-token
          key: PULUMI_ACCESS_TOKEN
          namespace: external-secrets-system
EOF
            print_status "✓ ClusterSecretStore を手動作成しました"
        fi
    else
        print_warning "ArgoCD external-secrets-config application が見つかりません"
        print_debug "手動でClusterSecretStoreを作成します..."
        # フォールバック: 手動作成
        cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: pulumi-esc-store
spec:
  provider:
    pulumi:
      organization: ksera
      project: k8s
      environment: secret
      accessToken:
        secretRef:
          name: pulumi-access-token
          key: PULUMI_ACCESS_TOKEN
          namespace: external-secrets-system
EOF
        print_status "✓ ClusterSecretStore を手動作成しました"
    fi
else
    print_debug "✓ ClusterSecretStore 設定確認完了"
fi

# ClusterSecretStore 接続待機
print_debug "ClusterSecretStore 接続待機中..."
timeout=60
while [ $timeout -gt 0 ]; do
    SECRETSTORE_STATUS=$(kubectl get clustersecretstore pulumi-esc-store -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    if [ "$SECRETSTORE_STATUS" = "True" ]; then
        print_status "✓ ClusterSecretStore 接続確認完了"
        break
    fi
    
    # 詳細なステータス確認
    if [ "$SECRETSTORE_STATUS" = "False" ]; then
        ERROR_MESSAGE=$(kubectl get clustersecretstore pulumi-esc-store -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "Unknown")
        print_warning "ClusterSecretStore接続エラー: $ERROR_MESSAGE"
        
        # Pulumi Access Token確認
        if ! kubectl get secret pulumi-access-token -n external-secrets-system >/dev/null 2>&1; then
            print_error "Pulumi Access Token Secretが見つかりません"
            exit 1
        fi
    fi
    
    echo "ClusterSecretStore 接続待機中... (残り ${timeout}秒) - Status: $SECRETSTORE_STATUS"
    sleep 5
    timeout=$((timeout - 5))
done

if [ $timeout -le 0 ]; then
    print_error "ClusterSecretStore 接続がタイムアウトしました"
    print_debug "最終ステータス: $SECRETSTORE_STATUS"
    if [ "$SECRETSTORE_STATUS" = "False" ]; then
        ERROR_MESSAGE=$(kubectl get clustersecretstore pulumi-esc-store -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "Unknown")
        print_error "接続エラー詳細: $ERROR_MESSAGE"
        print_warning "Pulumi ESCのアクセストークンまたは権限を確認してください"
    fi
    print_debug "詳細確認: kubectl describe clustersecretstore pulumi-esc-store"
    print_warning "External Secretsが利用できません。フォールバックモードに切り替えます"
    exit 1
fi

print_status "✓ 前提条件確認完了"

# 必要なネームスペース作成
print_status "必要なネームスペースを作成中..."

NAMESPACES=(
    "harbor"
    "arc-systems"
    "cloudflared"
    "default"
    "sandbox"
    "production" 
    "staging"
)

for namespace in "${NAMESPACES[@]}"; do
    if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
        print_debug "ネームスペース $namespace を作成中..."
        kubectl create namespace "$namespace"
        print_status "✓ ネームスペース $namespace を作成"
    else
        print_debug "ネームスペース $namespace は既に存在"
    fi
done

# Harbor ExternalSecrets の適用確認・作成
print_status "Harbor ExternalSecrets を確認中..."

# ArgoCD経由でのExternalSecrets作成を確認
if kubectl get application external-secrets-config -n argocd >/dev/null 2>&1; then
    # ArgoCD同期を促進してExternalSecretsを作成
    print_debug "ArgoCD external-secrets-config同期を促進中..."
    kubectl patch application external-secrets-config -n argocd -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type=merge 2>/dev/null || true
    
    # ExternalSecret作成待機
    timeout=120
    while [ $timeout -gt 0 ]; do
        if kubectl get externalsecret harbor-admin-secret -n harbor >/dev/null 2>&1; then
            print_status "✓ Harbor ExternalSecrets が作成されました"
            break
        fi
        echo "Harbor ExternalSecrets作成待機中... (残り ${timeout}秒)"
        sleep 10
        timeout=$((timeout - 10))
    done
    
    if [ $timeout -le 0 ]; then
        print_warning "ArgoCD経由でのExternalSecrets作成がタイムアウトしました"
        print_debug "手動でExternalSecretsを作成します..."
        # フォールバック: 手動作成
        cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: harbor-admin-secret
  namespace: harbor
spec:
  refreshInterval: 20s
  secretStoreRef:
    name: pulumi-esc-store
    kind: ClusterSecretStore
  target:
    name: harbor-admin-secret
    creationPolicy: Owner
    template:
      type: Opaque
      engineVersion: v2
      data:
        username: "admin"
        password: "{{ .harbor | default \"Harbor12345\" }}"
        HARBOR_CI_PASSWORD: "{{ .harbor_ci | default \"Harbor12345\" }}"
  data:
  - secretKey: harbor
    remoteRef:
      key: harbor
  - secretKey: harbor_ci
    remoteRef:
      key: harbor_ci
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: harbor-auth-secret
  namespace: arc-systems
spec:
  refreshInterval: 20s
  secretStoreRef:
    name: pulumi-esc-store
    kind: ClusterSecretStore
  target:
    name: harbor-auth
    creationPolicy: Owner
    template:
      type: Opaque
      engineVersion: v2
      data:
        HARBOR_USERNAME: "admin"
        HARBOR_PASSWORD: "{{ .harbor | default \"Harbor12345\" }}"
        HARBOR_URL: "192.168.122.100"
        HARBOR_PROJECT: "sandbox"
  data:
  - secretKey: harbor
    remoteRef:
      key: harbor
EOF
        print_status "✓ Harbor ExternalSecrets を手動作成しました"
    fi
else
    print_warning "ArgoCD external-secrets-config application が見つかりません"
    print_debug "手動でExternalSecretsを作成します..."
    # フォールバック: 手動作成
    cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: harbor-admin-secret
  namespace: harbor
spec:
  refreshInterval: 20s
  secretStoreRef:
    name: pulumi-esc-store
    kind: ClusterSecretStore
  target:
    name: harbor-admin-secret
    creationPolicy: Owner
    template:
      type: Opaque
      engineVersion: v2
      data:
        username: "admin"
        password: "{{ .harbor | default \"Harbor12345\" }}"
        HARBOR_CI_PASSWORD: "{{ .harbor_ci | default \"Harbor12345\" }}"
  data:
  - secretKey: harbor
    remoteRef:
      key: harbor
  - secretKey: harbor_ci
    remoteRef:
      key: harbor_ci
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: harbor-auth-secret
  namespace: arc-systems
spec:
  refreshInterval: 20s
  secretStoreRef:
    name: pulumi-esc-store
    kind: ClusterSecretStore
  target:
    name: harbor-auth
    creationPolicy: Owner
    template:
      type: Opaque
      engineVersion: v2
      data:
        HARBOR_USERNAME: "admin"
        HARBOR_PASSWORD: "{{ .harbor | default \"Harbor12345\" }}"
        HARBOR_URL: "192.168.122.100"
        HARBOR_PROJECT: "sandbox"
  data:
  - secretKey: harbor
    remoteRef:
      key: harbor
EOF
    print_status "✓ Harbor ExternalSecrets を手動作成しました"
fi

# ExternalSecret の同期を待機
print_status "External Secrets の同期を待機中..."

# Harbor admin secret の同期待機
print_debug "harbor-admin-secret の同期待機中..."
timeout=120
while [ $timeout -gt 0 ]; do
    if kubectl get secret harbor-admin-secret -n harbor >/dev/null 2>&1; then
        print_status "✓ harbor-admin-secret 同期完了"
        break
    fi
    echo "Harbor admin secret 同期待機中... (残り ${timeout}秒)"
    sleep 5
    timeout=$((timeout - 5))
done

if [ $timeout -le 0 ]; then
    print_error "harbor-admin-secret の同期がタイムアウトしました"
    print_warning "Pulumi ESCにharborキーが存在しない可能性があります"
    print_debug "詳細確認: kubectl describe externalsecret harbor-admin-secret -n harbor"
    print_warning "External Secretsが利用できません。フォールバックモードに切り替えます"
    exit 1
fi

# Harbor auth secret (arc-systems) の同期確認
print_debug "harbor-auth の同期確認中..."
if kubectl get secret harbor-auth -n arc-systems >/dev/null 2>&1; then
    print_status "✓ harbor-auth は既に同期済みです"
else
    print_debug "harbor-auth の同期待機中..."
    timeout=60
    while [ $timeout -gt 0 ]; do
        if kubectl get secret harbor-auth -n arc-systems >/dev/null 2>&1; then
            print_status "✓ harbor-auth 同期完了"
            break
        fi
        echo "Harbor auth secret 同期待機中... (残り ${timeout}秒)"
        sleep 5
        timeout=$((timeout - 5))
    done
    
    if [ $timeout -le 0 ]; then
        print_warning "harbor-auth の同期がタイムアウトしましたが、処理を続行します"
        print_debug "詳細確認: kubectl describe externalsecret harbor-auth-secret -n arc-systems"
    fi
fi

# External Secrets による主要な認証情報確認
print_status "=== 主要な External Secrets 確認 ==="
print_debug "harbor-admin-secret (harbor namespace): $(kubectl get secret harbor-admin-secret -n harbor >/dev/null 2>&1 && echo "✓" || echo "❌")"
print_debug "harbor-auth (arc-systems namespace): $(kubectl get secret harbor-auth -n arc-systems >/dev/null 2>&1 && echo "✓" || echo "❌")"
print_debug "cloudflared (cloudflared namespace): $(kubectl get secret cloudflared -n cloudflared >/dev/null 2>&1 && echo "✓" || echo "❌")"
print_debug "github-auth (arc-systems namespace): $(kubectl get secret github-auth -n arc-systems >/dev/null 2>&1 && echo "✓" || echo "❌")"

print_status "=== Harbor 認証情報デプロイ完了 ==="

# 作成結果の確認
print_status "作成されたSecretの確認:"
echo "  Harbor Admin Secret:"
if kubectl get secret harbor-admin-secret -n harbor >/dev/null 2>&1; then
    echo "    ✓ harbor: harbor-admin-secret"
else
    echo "    ❌ harbor: harbor-admin-secret (作成失敗)"
fi

echo "  Harbor Registry Secrets:"
if kubectl get secret harbor-registry-secret -n arc-systems >/dev/null 2>&1; then
    echo "    ✓ arc-systems: harbor-registry-secret"
else
    echo "    ❌ arc-systems: harbor-registry-secret (作成失敗)"
fi

echo "  Harbor HTTP Secrets:"
for namespace in "default" "sandbox" "production" "staging"; do
    if kubectl get secret harbor-http -n "$namespace" >/dev/null 2>&1; then
        echo "    ✓ $namespace: harbor-http"
    else
        echo "    ❌ $namespace: harbor-http (作成失敗)"
    fi
done

echo ""
print_status "使用方法:"
echo "  Deployment/Pod の imagePullSecrets に以下を追加:"
echo "  imagePullSecrets:"
echo "  - name: harbor-http"
echo ""
print_status "Harbor認証情報:"
echo "  Registry: 192.168.122.100"
echo "  Username: admin"
echo "  Password: (Pulumi ESC から自動取得)"
echo ""
print_status "確認コマンド:"
echo "  kubectl get externalsecrets -A"
echo "  kubectl describe externalsecret harbor-admin-secret -n harbor"