#!/bin/bash

# Kubernetes基盤構築スクリプト
# MetalLB + Ingress Controller + cert-manager + ArgoCD + Harbor

set -euo pipefail

# GitHub認証情報管理ユーティリティを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/github-auth-utils.sh"

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

print_status "=== Kubernetes基盤構築開始 ==="

# 0. マニフェストファイルの準備
print_status "マニフェストファイルをリモートにコピー中..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scp -o StrictHostKeyChecking=no "$SCRIPT_DIR/manifests/metallb-ipaddress-pool.yaml" k8suser@192.168.122.10:/tmp/
scp -o StrictHostKeyChecking=no "$SCRIPT_DIR/manifests/cert-manager-selfsigned-issuer.yaml" k8suser@192.168.122.10:/tmp/
scp -o StrictHostKeyChecking=no "$SCRIPT_DIR/manifests/local-storage-class.yaml" k8suser@192.168.122.10:/tmp/
scp -o StrictHostKeyChecking=no "$SCRIPT_DIR/manifests/argocd-ingress.yaml" k8suser@192.168.122.10:/tmp/
scp -o StrictHostKeyChecking=no "$SCRIPT_DIR/manifests/app-of-apps.yaml" k8suser@192.168.122.10:/tmp/
scp -o StrictHostKeyChecking=no "$SCRIPT_DIR/manifests/slack-externalsecret.yaml" k8suser@192.168.122.10:/tmp/
print_status "✓ マニフェストファイルコピー完了"

# 1. 前提条件確認
print_status "前提条件を確認中..."

# SSH known_hosts クリーンアップ
print_debug "SSH known_hosts をクリーンアップ中..."
ssh-keygen -f "$HOME/.ssh/known_hosts" -R '192.168.122.10' 2>/dev/null || true
ssh-keygen -f "$HOME/.ssh/known_hosts" -R '192.168.122.11' 2>/dev/null || true  
ssh-keygen -f "$HOME/.ssh/known_hosts" -R '192.168.122.12' 2>/dev/null || true

# k8sクラスタ接続確認
print_debug "k8sクラスタ接続を確認中..."
if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
    print_error "k8sクラスタに接続できません"
    print_error "Phase 3のk8sクラスタ構築を先に完了してください"
    print_error "注意: このスクリプトはUbuntuホストマシンで実行してください（WSL2不可）"
    exit 1
fi

READY_NODES=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get nodes --no-headers' | grep -c Ready || echo "0")
if [[ $READY_NODES -lt 2 ]]; then
    print_error "Ready状態のNodeが2台未満です（現在: $READY_NODES台）"
    exit 1
elif [[ $READY_NODES -eq 2 ]]; then
    print_warning "Ready状態のNodeが2台です（推奨: 3台）"
    print_debug "Node状態を確認中..."
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get nodes'
    
    # Worker Node追加を試行
    print_debug "3台目のWorker Node参加を試行中..."
    JOIN_CMD=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubeadm token create --print-join-command' 2>/dev/null || echo "")
    if [[ -n "$JOIN_CMD" ]]; then
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 k8suser@192.168.122.12 "sudo $JOIN_CMD" >/dev/null 2>&1; then
            print_status "✓ 3台目のWorker Node参加成功"
            sleep 30
            READY_NODES=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get nodes --no-headers' | grep -c Ready || echo "0")
        else
            print_warning "3台目のWorker Node参加に失敗しました（2台構成で続行）"
        fi
    fi
elif [[ $READY_NODES -gt 3 ]]; then
    print_warning "Ready状態のNodeが3台を超えています（現在: $READY_NODES台）"
fi

print_status "✓ k8sクラスタ（$READY_NODES Node）接続OK"

# 1. MetalLB インストール
print_status "=== Phase 4.1: MetalLB インストール ==="
print_debug "LoadBalancer機能を提供します"

ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
# MetalLB namespace作成
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

# MetalLB起動まで待機
echo "MetalLB Pod起動を待機中..."
kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=300s

# IPアドレスプール設定（libvirtデフォルトネットワーク範囲）
kubectl apply -f /tmp/metallb-ipaddress-pool.yaml

echo "✓ MetalLB設定完了"
EOF

print_status "✓ MetalLB インストール完了"

# 2. Ingress Controller (NGINX) インストール
print_status "=== Phase 4.2: NGINX Ingress Controller インストール ==="
print_debug "HTTP/HTTPSルーティング機能を提供します"

ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
# NGINX Ingress Controller インストール
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml

# Ingress Controller起動まで待機
echo "NGINX Ingress Controller起動を待機中..."
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s

# LoadBalancer ServiceのIP確認
echo "LoadBalancer IP確認中..."
kubectl -n ingress-nginx get service ingress-nginx-controller

echo "✓ NGINX Ingress Controller設定完了"
EOF

print_status "✓ NGINX Ingress Controller インストール完了"

# 3. cert-manager インストール
print_status "=== Phase 4.3: cert-manager インストール ==="
print_debug "TLS証明書自動管理機能を提供します"

ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
# cert-manager インストール
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# cert-manager起動まで待機
echo "cert-manager起動を待機中..."
kubectl wait --namespace cert-manager --for=condition=ready pod --selector=app.kubernetes.io/instance=cert-manager --timeout=300s

# Self-signed ClusterIssuer作成（開発用）
kubectl apply -f /tmp/cert-manager-selfsigned-issuer.yaml

echo "✓ cert-manager設定完了"
EOF

print_status "✓ cert-manager インストール完了"

# 4. StorageClass設定
print_status "=== Phase 4.4: StorageClass設定 ==="
print_debug "永続ストレージ機能を設定します"

ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
# Local StorageClass作成
kubectl apply -f /tmp/local-storage-class.yaml

echo "✓ StorageClass設定完了"
EOF

print_status "✓ StorageClass設定完了"

# 5. ArgoCD インストール
print_status "=== Phase 4.5: ArgoCD インストール ==="
print_debug "GitOps継続的デプロイメント機能を提供します"

ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
# ArgoCD namespace作成・インストール
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# ArgoCD起動まで待機
echo "ArgoCD起動を待機中..."
kubectl wait --namespace argocd --for=condition=ready pod --selector=app.kubernetes.io/component=server --timeout=300s

# ArgoCD insecureモード設定（HTTPアクセス対応）
echo "ArgoCD insecureモード設定中..."
kubectl patch configmap argocd-cmd-params-cm -n argocd -p '{"data":{"server.insecure":"true"}}'

# ArgoCD管理者パスワード取得・表示
echo "ArgoCD管理者パスワード:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""

# ArgoCD Ingress設定（HTTP対応）
kubectl apply -f /tmp/argocd-ingress.yaml

# ArgoCD サーバー再起動（insecure設定反映）
echo "ArgoCD サーバー再起動中..."
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd --timeout=300s

echo "✓ ArgoCD Ingress設定完了"
echo "✓ ArgoCD設定完了"
EOF

print_status "✓ ArgoCD インストール完了"

# 6. Harbor パスワード設定
print_status "=== Phase 4.6: Harbor パスワード設定 ==="
print_debug "Harbor管理者パスワードを設定します"

# External Secrets による Harbor 認証情報管理
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTERNAL_SECRETS_ENABLED=false

# PULUMI_ACCESS_TOKEN事前確認・入力受付
if [[ -f "$SCRIPT_DIR/external-secrets/setup-external-secrets.sh" ]]; then
    print_debug "External Secrets による Harbor 認証情報を設定中..."
    print_debug "Pulumi ESC から Harbor パスワードを自動取得します"
    
    # PULUMI_ACCESS_TOKEN対話的設定
    if [ -z "${PULUMI_ACCESS_TOKEN:-}" ]; then
        print_status "External Secrets を使用するためにPulumi Access Tokenが必要です"
        print_status "取得方法: https://app.pulumi.com/account/tokens"
        echo ""
        echo -n "Pulumi Access Token (pul-で始まる、Enterでスキップ): "
        read -s PULUMI_ACCESS_TOKEN_INPUT
        echo
        
        if [ -n "${PULUMI_ACCESS_TOKEN_INPUT:-}" ]; then
            # PAT形式検証
            PULUMI_ACCESS_TOKEN_INPUT=$(echo "$PULUMI_ACCESS_TOKEN_INPUT" | tr -d '[:space:]')
            if [[ "$PULUMI_ACCESS_TOKEN_INPUT" =~ ^pul-[a-f0-9]{40}$ ]]; then
                export PULUMI_ACCESS_TOKEN="$PULUMI_ACCESS_TOKEN_INPUT"
                print_status "✓ Pulumi Access Token設定完了"
            else
                print_warning "Pulumi Access Tokenの形式が正しく見えません"
                echo -n "続行しますか？ [y/N]: "
                read -r response
                case "$response" in
                    [yY][eE][sS]|[yY])
                        export PULUMI_ACCESS_TOKEN="$PULUMI_ACCESS_TOKEN_INPUT"
                        print_status "✓ Pulumi Access Token設定完了（形式警告を無視）"
                        ;;
                    *)
                        print_debug "トークン入力がキャンセルされました。フォールバックモードを使用します"
                        EXTERNAL_SECRETS_ENABLED=false
                        ;;
                esac
            fi
        else
            print_debug "トークン入力がスキップされました。フォールバックモードを使用します"
            EXTERNAL_SECRETS_ENABLED=false
        fi
    fi
    
    # External Secrets Operator のインストール状況確認
    # HelmでデプロイされたExternal Secrets Operatorの検出
    ESO_DEPLOYMENT_CHECK=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get deployments -n external-secrets-system --no-headers 2>/dev/null | grep -E "(external-secrets|eso)" | wc -l' 2>/dev/null || echo "0")
    
    if [ "$ESO_DEPLOYMENT_CHECK" = "0" ]; then
        print_warning "External Secrets Operator が見つかりません"
        print_status "HelmでExternal Secrets Operatorを直接デプロイします"
        
        # 事前準備: namespace作成とSecret設定
        print_debug "事前準備: namespace作成とSecret設定実行中..."
        ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
# external-secrets-system namespace作成
kubectl create namespace external-secrets-system --dry-run=client -o yaml | kubectl apply -f -
echo "✓ external-secrets-system namespace作成完了"

# harbor namespace作成（SecretStore用）
kubectl create namespace harbor --dry-run=client -o yaml | kubectl apply -f -
echo "✓ harbor namespace作成完了"

# arc-systems namespace作成（Harbor Registry Secret用）
kubectl create namespace arc-systems --dry-run=client -o yaml | kubectl apply -f -
echo "✓ arc-systems namespace作成完了"
EOF
        
        # Pulumi Access Token の確認・事前設定
        if [ -n "${PULUMI_ACCESS_TOKEN:-}" ]; then
            print_debug "Pulumi Access Tokenを事前設定中..."
            # 環境変数をファイルに書き出してSSH転送
            echo "$PULUMI_ACCESS_TOKEN" > /tmp/pulumi_token.tmp
            scp /tmp/pulumi_token.tmp k8suser@192.168.122.10:/tmp/
            rm -f /tmp/pulumi_token.tmp
            
            ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
# ファイルからPATを読み取り
PAT_TOKEN=$(cat /tmp/pulumi_token.tmp)
rm -f /tmp/pulumi_token.tmp

# 各namespaceにPulumi Access Token Secretを作成
for namespace in external-secrets-system harbor arc-systems; do
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret generic pulumi-access-token \
        --from-literal=PULUMI_ACCESS_TOKEN="$PAT_TOKEN" \
        --namespace="$namespace" \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "✓ pulumi-access-token Secret作成完了: $namespace"
done
EOF
            if [ $? -eq 0 ]; then
                print_status "✓ Pulumi Access Token事前設定完了"
            else
                print_warning "Pulumi Access Token事前設定に失敗しました"
            fi
        else
            print_warning "PULUMI_ACCESS_TOKEN環境変数が設定されていません"
            print_warning "External Secrets機能は制限されます"
        fi
        
        # Helmデプロイスクリプトが存在する場合は実行
        if [[ -f "$SCRIPT_DIR/external-secrets/helm-deploy-eso.sh" ]]; then
            print_debug "HelmでExternal Secrets Operatorデプロイ実行中..."
            if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "cd /tmp && cat > helm-deploy-eso.sh" < "$SCRIPT_DIR/external-secrets/helm-deploy-eso.sh"; then
                # PULUMI_ACCESS_TOKEN環境変数をリモートに渡して実行
                ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "chmod +x /tmp/helm-deploy-eso.sh && PULUMI_ACCESS_TOKEN='${PULUMI_ACCESS_TOKEN:-}' /tmp/helm-deploy-eso.sh"
                
                if [ $? -eq 0 ]; then
                    print_status "✓ HelmでExternal Secrets Operatorデプロイ完了"
                    EXTERNAL_SECRETS_ENABLED=true
                    
                    # ArgoCD管理に移行
                    print_debug "ArgoCD管理に移行中..."
                    if [[ -f "$SCRIPT_DIR/external-secrets/migrate-to-argocd.sh" ]] && grep -q "external-secrets-operator" "../../infra/app-of-apps.yaml"; then
                        if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "cd /tmp && cat > migrate-to-argocd.sh" < "$SCRIPT_DIR/external-secrets/migrate-to-argocd.sh"; then
                            ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "chmod +x /tmp/migrate-to-argocd.sh && /tmp/migrate-to-argocd.sh" || true
                            print_debug "✓ ArgoCD管理移行完了（または実行済み）"
                        fi
                    else
                        print_debug "ArgoCD管理移行はスキップされました（App-of-Apps未設定）"
                    fi
                else
                    print_warning "HelmでのExternal Secrets Operatorデプロイに失敗しました"
                    EXTERNAL_SECRETS_ENABLED=false
                fi
            else
                print_error "Helmデプロイスクリプトの転送に失敗しました"
                EXTERNAL_SECRETS_ENABLED=false
            fi
        else
            print_warning "Helmデプロイスクリプトが見つかりません"
            print_warning "フォールバックモードに切り替えます"
            EXTERNAL_SECRETS_ENABLED=false
        fi
    else
        # Deploymentが存在する場合、Podが実際にReadyかも確認
        ESO_READY_CHECK=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get pods -n external-secrets-system --no-headers 2>/dev/null | grep -E "(external-secrets|eso)" | grep -c "1/1.*Running"' 2>/dev/null || echo "0")
        
        if [ "$ESO_READY_CHECK" -gt "0" ]; then
            print_debug "✓ External Secrets Operator は既にインストール済み（${ESO_DEPLOYMENT_CHECK}個のDeployment、${ESO_READY_CHECK}個のPod稼働中）"
            EXTERNAL_SECRETS_ENABLED=true
        else
            print_warning "External Secrets Operator のDeploymentは存在しますが、Podが稼働していません"
            print_debug "Pod状態確認中..."
            timeout=60
            while [ $timeout -gt 0 ]; do
                ESO_READY_RECHECK=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get pods -n external-secrets-system --no-headers 2>/dev/null | grep -E "(external-secrets|eso)" | grep -c "1/1.*Running"' 2>/dev/null || echo "0")
                if [ "$ESO_READY_RECHECK" -gt "0" ]; then
                    print_status "✓ External Secrets Operator Pod稼働確認完了"
                    EXTERNAL_SECRETS_ENABLED=true
                    break
                fi
                echo "External Secrets Operator Pod起動待機中... (残り ${timeout}秒)"
                sleep 10
                timeout=$((timeout - 10))
            done
            
            if [ $timeout -le 0 ]; then
                print_warning "External Secrets Operator PodがReady状態になりませんでした"
                print_warning "フォールバックモードに切り替えます"
                EXTERNAL_SECRETS_ENABLED=false
            fi
        fi
    fi
    
    # ArgoCD App-of-Apps同期とExternal Secrets作成を待機
    if [ "$EXTERNAL_SECRETS_ENABLED" = true ]; then
        print_debug "ArgoCD App-of-Apps同期とExternal Secrets作成を待機中..."
        
        # ArgoCD infrastructure applicationが存在するかチェック
        if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get application infrastructure -n argocd' >/dev/null 2>&1; then
            print_debug "ArgoCD infrastructure application同期を促進中..."
            ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl patch application infrastructure -n argocd --type json -p="[{\"op\": \"replace\", \"path\": \"/metadata/annotations/argocd.argoproj.io~1refresh\", \"value\": \"hard\"}]"' >/dev/null 2>&1 || true
            
            # external-secrets-config applicationの同期待機
            timeout=120
            while [ $timeout -gt 0 ]; do
                if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get application external-secrets-config -n argocd' >/dev/null 2>&1; then
                    # external-secrets-config同期を促進
                    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl patch application external-secrets-config -n argocd --type json -p="[{\"op\": \"replace\", \"path\": \"/metadata/annotations/argocd.argoproj.io~1refresh\", \"value\": \"hard\"}]"' >/dev/null 2>&1 || true
                    print_status "✓ ArgoCD external-secrets-config application同期完了"
                    break
                fi
                echo "ArgoCD external-secrets-config application作成待機中... (残り ${timeout}秒)"
                sleep 10
                timeout=$((timeout - 10))
            done
            
            if [ $timeout -le 0 ]; then
                print_warning "ArgoCD external-secrets-config application作成がタイムアウトしました"
                print_debug "External Secretsの手動作成を試行します"
            else
                # GitHub ExternalSecretの作成待機
                timeout=60
                while [ $timeout -gt 0 ]; do
                    if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get externalsecret github-auth-secret -n arc-systems' >/dev/null 2>&1; then
                        print_status "✓ GitHub ExternalSecret作成完了"
                        break
                    fi
                    echo "GitHub ExternalSecret作成待機中... (残り ${timeout}秒)"
                    sleep 5
                    timeout=$((timeout - 5))
                done
                
                if [ $timeout -le 0 ]; then
                    print_warning "GitHub ExternalSecret作成がタイムアウトしました"
                fi
            fi
        else
            print_debug "ArgoCD infrastructure applicationが見つかりません"
        fi
    fi
    
    # External Secrets が利用可能な場合の処理
    if [ "$EXTERNAL_SECRETS_ENABLED" = true ]; then
        # Pulumi Access Token の確認・設定
        if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret pulumi-access-token -n external-secrets-system' >/dev/null 2>&1; then
            # 環境変数から取得を試行
            if [ -n "${PULUMI_ACCESS_TOKEN:-}" ]; then
                print_debug "環境変数からPulumi Access Tokenを設定中..."
                echo "$PULUMI_ACCESS_TOKEN" | ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
                    'cd /tmp && cat > pulumi-pat.txt && kubectl create secret generic pulumi-access-token --from-literal=PULUMI_ACCESS_TOKEN="$(cat pulumi-pat.txt)" -n external-secrets-system && rm -f pulumi-pat.txt'
                if [ $? -eq 0 ]; then
                    print_status "✓ 環境変数からPulumi Access Token設定完了"
                    # 他のネームスペースにもコピー
                    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
for ns in harbor arc-systems; do
    kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
    kubectl get secret pulumi-access-token -n external-secrets-system -o yaml | sed "s/namespace: external-secrets-system/namespace: $ns/" | kubectl apply -f -
done
EOF
                else
                    print_error "環境変数からのPulumi Access Token設定に失敗しました"
                    EXTERNAL_SECRETS_ENABLED=false
                fi
            else
                print_warning "Pulumi Access Token が提供されていません"
                print_warning "フォールバックモードに切り替えます"
                EXTERNAL_SECRETS_ENABLED=false
            fi
        fi
        
        # External Secrets による Harbor Secrets デプロイ
        if [ "$EXTERNAL_SECRETS_ENABLED" = true ] && ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret pulumi-access-token -n external-secrets-system' >/dev/null 2>&1; then
            # deploy-harbor-secrets.shをリモートで実行
            DEPLOY_RESULT=0
            if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "cd /tmp && cat > deploy-harbor-secrets.sh" < "$SCRIPT_DIR/external-secrets/deploy-harbor-secrets.sh"; then
                ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "chmod +x /tmp/deploy-harbor-secrets.sh && /tmp/deploy-harbor-secrets.sh"
                DEPLOY_RESULT=$?
            else
                DEPLOY_RESULT=1
            fi
            
            if [ $DEPLOY_RESULT -eq 0 ]; then
                # External Secrets からパスワードを取得
                HARBOR_PASSWORD=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
                    'kubectl get secret harbor-admin-secret -n harbor -o jsonpath="{.data.password}" | base64 -d' 2>/dev/null || echo "Harbor12345")
                HARBOR_USERNAME="admin"
                export HARBOR_PASSWORD HARBOR_USERNAME
                
                # External Secretsが成功した場合の確認
                if [[ "$HARBOR_PASSWORD" != "Harbor12345" ]] && [[ -n "$HARBOR_PASSWORD" ]]; then
                    print_status "✓ External Secrets による Harbor パスワード自動取得成功"
                    print_debug "Pulumi ESCから取得したパスワードを使用します"
                else
                    print_warning "External Secrets でのパスワード取得に失敗、デフォルトパスワードを使用"
                    EXTERNAL_SECRETS_ENABLED=false
                fi
                print_debug "✓ External Secrets による Harbor 認証情報管理完了"
                
                # Slack Secrets デプロイ
                print_status "Slack 認証情報を External Secrets で設定中..."
                if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "cd /tmp && cat > deploy-slack-secrets.sh" < "$SCRIPT_DIR/external-secrets/deploy-slack-secrets.sh"; then
                    if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "chmod +x /tmp/deploy-slack-secrets.sh && /tmp/deploy-slack-secrets.sh"; then
                        print_debug "✓ External Secrets による Slack 認証情報管理完了"
                    else
                        print_warning "Slack Secret作成に失敗しました（Pulumi ESCにslack secretが未設定の可能性）"
                    fi
                else
                    print_warning "Slack Secret デプロイスクリプトの転送に失敗しました"
                fi
            else
                print_warning "External Secrets による Harbor Secret作成に失敗しました"
                print_warning "フォールバックモードに切り替えます"
                EXTERNAL_SECRETS_ENABLED=false
            fi
        else
            EXTERNAL_SECRETS_ENABLED=false
        fi
    fi
# External Secrets が利用できない場合のフォールバック処理
if [ "$EXTERNAL_SECRETS_ENABLED" = false ]; then
    print_warning "External Secrets が利用できません。従来の手動管理にフォールバック中..."
    if [[ -f "$SCRIPT_DIR/harbor-password-manager.sh" ]]; then
        bash "$SCRIPT_DIR/harbor-password-manager.sh"
        HARBOR_PASSWORD=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
            'kubectl get secret harbor-admin-secret -n harbor -o jsonpath="{.data.password}" | base64 -d' 2>/dev/null || echo "Harbor12345")
        HARBOR_USERNAME="admin"
        export HARBOR_PASSWORD HARBOR_USERNAME
        print_debug "✓ フォールバック Harbor パスワード管理完了"
    else
        print_warning "Harbor パスワード管理スクリプトが見つかりません。デフォルトパスワードを使用します"
        HARBOR_PASSWORD="Harbor12345"
        HARBOR_USERNAME="admin"
        export HARBOR_PASSWORD HARBOR_USERNAME
    fi
fi
else
    # External Secrets 関連ファイルが見つからない場合
    print_warning "External Secrets 設定ファイルが見つかりません。従来の手動管理を使用します"
    if [[ -f "$SCRIPT_DIR/harbor-password-manager.sh" ]]; then
        bash "$SCRIPT_DIR/harbor-password-manager.sh"
        HARBOR_PASSWORD=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
            'kubectl get secret harbor-admin-secret -n harbor -o jsonpath="{.data.password}" | base64 -d' 2>/dev/null || echo "Harbor12345")
        HARBOR_USERNAME="admin"
        export HARBOR_PASSWORD HARBOR_USERNAME
        print_debug "✓ 従来の Harbor パスワード管理完了"
    else
        print_warning "Harbor パスワード管理スクリプトが見つかりません。デフォルトパスワードを使用します"
        HARBOR_PASSWORD="Harbor12345"
        HARBOR_USERNAME="admin"
        export HARBOR_PASSWORD HARBOR_USERNAME
    fi
fi

# GitHub Actions用Secret作成確認と修正
print_debug "GitHub Actions用Secret作成確認・修正中..."
HARBOR_AUTH_SECRET=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
    'kubectl get secret harbor-auth -n arc-systems -o jsonpath="{.data.HARBOR_USERNAME}" | base64 -d' 2>/dev/null || echo "")

if [[ -n "$HARBOR_AUTH_SECRET" ]]; then
    # Secret存在確認後、必要なフィールドが揃っているかチェック
    HARBOR_URL_CHECK=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
        'kubectl get secret harbor-auth -n arc-systems -o jsonpath="{.data.HARBOR_URL}" | base64 -d' 2>/dev/null || echo "")
    HARBOR_PROJECT_CHECK=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
        'kubectl get secret harbor-auth -n arc-systems -o jsonpath="{.data.HARBOR_PROJECT}" | base64 -d' 2>/dev/null || echo "")
    
    if [[ -z "$HARBOR_URL_CHECK" ]] || [[ -z "$HARBOR_PROJECT_CHECK" ]]; then
        print_warning "Harbor Secret不完全、修正中..."
        ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
# Harbor認証Secret完全版作成/更新
kubectl create secret generic harbor-auth \
    --from-literal=HARBOR_USERNAME="admin" \
    --from-literal=HARBOR_PASSWORD="${HARBOR_PASSWORD:-Harbor12345}" \
    --from-literal=HARBOR_URL="192.168.122.100" \
    --from-literal=HARBOR_PROJECT="sandbox" \
    --namespace=arc-systems \
    --dry-run=client -o yaml | kubectl apply -f -
echo "✓ Harbor Secret修正完了"
EOF
    fi
    print_debug "✓ GitHub Actions用Secret作成完了"
else
    print_warning "GitHub Actions用Secret作成に失敗しました"
    print_debug "ARCセットアップ時に再試行されます"

# 7. Harbor Namespace とSecret作成
print_status "=== Phase 4.7: Harbor Secret作成 ==="
print_debug "Harbor管理者認証情報をSecret化します"

ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << EOF
# Harbor namespace作成（まだ存在しない場合）
kubectl create namespace harbor --dry-run=client -o yaml | kubectl apply -f -

# Harbor管理者パスワードSecret作成/更新
# External Secrets 使用時はスキップ（既にExternal Secretsで管理されている）
if [ "$EXTERNAL_SECRETS_ENABLED" != "true" ]; then
    kubectl create secret generic harbor-admin-secret \
        --from-literal=username="$HARBOR_USERNAME" \
        --from-literal=password="$HARBOR_PASSWORD" \
        --namespace=harbor \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "✓ Harbor管理者パスワードSecret作成（手動管理モード）"
else
    echo "✓ Harbor管理者パスワードSecret管理（External Secrets使用）"
fi

# ARC namespace作成（まだ存在しない場合）
kubectl create namespace arc-systems --dry-run=client -o yaml | kubectl apply -f -

# Harbor認証Secret（GitHub Actions用）作成/更新
kubectl create secret generic harbor-auth \
    --from-literal=HARBOR_USERNAME="$HARBOR_USERNAME" \
    --from-literal=HARBOR_PASSWORD="$HARBOR_PASSWORD" \
    --from-literal=HARBOR_URL="192.168.122.100" \
    --from-literal=HARBOR_PROJECT="sandbox" \
    --namespace=arc-systems \
    --dry-run=client -o yaml | kubectl apply -f -
    
# default namespace用も作成
kubectl create secret generic harbor-auth \
    --from-literal=HARBOR_USERNAME="$HARBOR_USERNAME" \
    --from-literal=HARBOR_PASSWORD="$HARBOR_PASSWORD" \
    --from-literal=HARBOR_URL="192.168.122.100" \
    --from-literal=HARBOR_PROJECT="sandbox" \
    --namespace=default \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Harbor Secret手動作成完了"
EOF
fi

# 7. App of Apps デプロイ
print_status "=== Phase 4.7: App of Apps デプロイ ==="
print_debug "GitOps経由でインフラとアプリケーションを管理します"

ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
# App of Apps をデプロイ
kubectl apply -f /tmp/app-of-apps.yaml

echo "✓ App of Apps デプロイ完了"
EOF

print_status "✓ GitOps セットアップ完了"

# 7.5. Harbor アプリケーション同期
print_status "=== Phase 4.7.5: Harbor アプリケーション同期 ==="
print_debug "Harbor パスワード設定をArgoCD経由で反映します"

ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
# ArgoCD Harbor アプリケーションの強制同期でSecret設定を反映
if kubectl get application harbor -n argocd >/dev/null 2>&1; then
    kubectl patch application harbor -n argocd -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type=merge
    echo "✓ Harbor アプリケーション同期リクエスト送信"
else
    echo "⚠️ Harbor アプリケーションがまだ存在しません（App of Apps デプロイ後に作成されます）"
fi
EOF

print_status "✓ Harbor アプリケーション同期完了"

# 8. GitHub Actions Runner Controller (ARC) セットアップ
print_status "=== Phase 4.8: GitHub Actions Runner Controller (ARC) セットアップ ==="
print_debug "GitHub Actions Self-hosted Runnerをk8s上にデプロイします"

# GitHub設定の確認・入力
if [[ -f "$SCRIPT_DIR/setup-arc.sh" ]]; then
    # GitHub設定の対話式確認
    echo ""
    print_status "GitHub Actions設定を確認中..."
    
    # GitHub ExternalSecret最終確認（get_github_credentials直前）
    if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get externalsecret github-auth-secret -n arc-systems' >/dev/null 2>&1; then
        # GitHub ExternalSecretが存在する場合、Ready状態を確認
        github_es_ready=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get externalsecret github-auth-secret -n arc-systems -o jsonpath="{.status.conditions[?(@.type==\"Ready\")].status}"' 2>/dev/null || echo "False")
        if [ "$github_es_ready" != "True" ]; then
            print_warning "GitHub ExternalSecretが準備できていません。同期を待機中..."
            # 60秒間待機
            timeout=60
            while [ $timeout -gt 0 ]; do
                github_es_ready=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get externalsecret github-auth-secret -n arc-systems -o jsonpath="{.status.conditions[?(@.type==\"Ready\")].status}"' 2>/dev/null || echo "False")
                if [ "$github_es_ready" = "True" ]; then
                    print_status "✓ GitHub ExternalSecret準備完了"
                    break
                fi
                echo "GitHub ExternalSecret同期待機中... (残り ${timeout}秒)"
                sleep 5
                timeout=$((timeout - 5))
            done
            
            if [ $timeout -le 0 ]; then
                print_warning "GitHub ExternalSecret同期がタイムアウトしました"
            fi
        else
            print_debug "✓ GitHub ExternalSecret準備完了"
        fi
    else
        print_debug "GitHub ExternalSecretが見つかりません（フォールバック動作）"
    fi
    
    # GitHub認証情報を取得（保存済みを利用または新規入力）
    if ! get_github_credentials; then
        print_warning "GitHub認証情報の取得に失敗しました"
        print_debug "ARCセットアップをスキップします"
    fi
    
    # Harbor認証情報の対話式確認
    if [[ -z "${HARBOR_USERNAME:-}" ]] || [[ -z "${HARBOR_PASSWORD:-}" ]]; then
        # External Secretsが成功している場合はスキップ
        if [ "$EXTERNAL_SECRETS_ENABLED" = true ]; then
            print_debug "External Secretsによる自動設定済み - Harbor認証情報の対話的入力をスキップします"
            print_debug "Harbor Username: ${HARBOR_USERNAME:-admin}"
            print_debug "Harbor Password: ${HARBOR_PASSWORD:0:3}*** (External Secrets経由で設定済み)"
        else
            echo ""
            print_status "Harbor認証情報を設定してください"
            
            # HARBOR_USERNAME入力
            if [[ -z "${HARBOR_USERNAME:-}" ]]; then
                echo "Harbor Registry Username (default: admin):"
                echo -n "HARBOR_USERNAME [admin]: "
                read HARBOR_USERNAME_INPUT
                if [[ -z "$HARBOR_USERNAME_INPUT" ]]; then
                    export HARBOR_USERNAME="admin"
                else
                    export HARBOR_USERNAME="$HARBOR_USERNAME_INPUT"
                fi
                print_debug "HARBOR_USERNAME設定完了: $HARBOR_USERNAME"
            fi
            
            # HARBOR_PASSWORD入力
            if [[ -z "${HARBOR_PASSWORD:-}" ]]; then
                echo "Harbor Registry Password (default: Harbor12345):"
                echo -n "HARBOR_PASSWORD [Harbor12345]: "
                read -s HARBOR_PASSWORD_INPUT
                echo ""
                if [[ -z "$HARBOR_PASSWORD_INPUT" ]]; then
                    export HARBOR_PASSWORD="Harbor12345"
                else
                    export HARBOR_PASSWORD="$HARBOR_PASSWORD_INPUT"
                fi
                print_debug "HARBOR_PASSWORD設定完了"
            fi
        fi
    else
        # Harbor認証情報が既に設定済みの場合
        print_debug "Harbor認証情報は既に設定済みです"
        print_debug "Harbor Username: ${HARBOR_USERNAME}"
        if [ "$EXTERNAL_SECRETS_ENABLED" = true ]; then
            print_debug "Harbor Password: *** (External Secrets経由で設定済み)"
        else
            print_debug "Harbor Password: ${HARBOR_PASSWORD:0:3}*** (事前設定済み)"
        fi
    fi
    
    # 設定確認とARC実行
    if [[ -n "${GITHUB_TOKEN:-}" ]] && [[ -n "${GITHUB_USERNAME:-}" ]]; then
        print_debug "ARC セットアップスクリプトを実行中..."
        print_debug "渡される値: HARBOR_USERNAME=$HARBOR_USERNAME, HARBOR_PASSWORD=${HARBOR_PASSWORD:0:3}..."
        # 環境変数をエクスポートして実行
        export GITHUB_TOKEN GITHUB_USERNAME HARBOR_USERNAME HARBOR_PASSWORD
        "$SCRIPT_DIR/setup-arc.sh"
    else
        print_warning "GitHub設定が不完全のため、ARC セットアップをスキップしました"
        print_warning "後で手動セットアップする場合："
        echo "  export GITHUB_TOKEN=YOUR_GITHUB_PERSONAL_ACCESS_TOKEN"
        echo "  export GITHUB_USERNAME=YOUR_GITHUB_USERNAME"
        echo "  bash $SCRIPT_DIR/setup-arc.sh"
    fi
else
    print_warning "setup-arc.shが見つかりません。ARCセットアップをスキップしました。"
fi

# 9. Cloudflaredセットアップ
print_status "=== Phase 4.9: Cloudflaredセットアップ ==="
print_debug "External Secrets経由でCloudflare Tunnel Secretを作成します"

# cloudflared namespace作成
print_debug "Cloudflared namespaceを作成中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl create namespace cloudflared --dry-run=client -o yaml | kubectl apply -f -"

# External Secretsが有効な場合
if [ "$EXTERNAL_SECRETS_ENABLED" = true ]; then
    print_debug "External Secrets経由でCloudflaredトークンを取得中..."
    
    # Cloudflared ExternalSecretの存在確認・作成を待機
    CLOUDFLARED_SECRET_READY=false
    timeout=60
    while [ $timeout -gt 0 ]; do
        if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret cloudflared -n cloudflared' >/dev/null 2>&1; then
            CLOUDFLARED_TOKEN_VALUE=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret cloudflared -n cloudflared -o jsonpath="{.data.token}" | base64 -d' 2>/dev/null || echo "")
            if [[ -n "$CLOUDFLARED_TOKEN_VALUE" ]] && [[ "$CLOUDFLARED_TOKEN_VALUE" != "" ]]; then
                print_status "✓ External SecretsでCloudflaredトークン取得成功"
                CLOUDFLARED_SECRET_READY=true
                break
            fi
        fi
        echo "Cloudflared Secret同期待機中... (残り ${timeout}秒)"
        sleep 5
        timeout=$((timeout - 5))
    done
    
    if [ "$CLOUDFLARED_SECRET_READY" = false ]; then
        print_warning "External SecretsでCloudflaredトークン取得に失敗しました"
        print_debug "Pulumi ESCにcloudflaredキーが存在しない可能性があります"
        EXTERNAL_SECRETS_ENABLED=false
    fi
fi

# External Secretsが利用できない場合のフォールバック
if [ "$EXTERNAL_SECRETS_ENABLED" = false ]; then
    print_warning "External Secretsが利用できません。手動でCloudflaredトークンを入力してください"
    echo ""
    echo "Cloudflare Tunnelのトークンを入力してください"
    echo "取得方法: https://one.dash.cloudflare.com/ > Access > Tunnels > Create Tunnel"
    echo "スキップしたい場合は空エンターを押してください"
    echo ""
    
    read -s -p "Cloudflared Token (空でスキップ): " CLOUDFLARED_TOKEN_INPUT
    echo ""
    
    if [[ -n "$CLOUDFLARED_TOKEN_INPUT" ]]; then
        print_debug "手動Cloudflared Secret作成中..."
        if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl create secret generic cloudflared --from-literal=token='$CLOUDFLARED_TOKEN_INPUT' --namespace=cloudflared --dry-run=client -o yaml | kubectl apply -f -"; then
            print_status "✓ 手動Cloudflared Secret作成完了"
        else
            print_warning "Cloudflared Secret作成に失敗しました"
        fi
    else
        print_warning "Cloudflaredトークンがスキップされました"
        print_debug "後で手動設定: kubectl create secret generic cloudflared --from-literal=token='YOUR_TOKEN' --namespace=cloudflared"
    fi
fi

# 10. Harbor sandboxプロジェクト作成
print_status "=== Phase 4.10: Harbor sandboxプロジェクト作成 ==="
print_debug "Harbor内にsandboxプライベートリポジトリを作成します"

# port-forwardプロセスのクリーンアップ用トラップ
cleanup_port_forward() {
    if [[ -n "${PORT_FORWARD_PID:-}" ]]; then
        kill $PORT_FORWARD_PID 2>/dev/null || true
        wait $PORT_FORWARD_PID 2>/dev/null || true
    fi
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'pkill -f "kubectl port-forward.*harbor-core" 2>/dev/null || true'
}

# スクリプト終了時のクリーンアップ
trap cleanup_port_forward EXIT

# 変数初期化
PORT_FORWARD_PID=""
HARBOR_IP=""
HARBOR_STATUS=""

# Harbor稼働確認
print_debug "Harbor稼働状況を確認中..."
HARBOR_READY=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get pods -n harbor --no-headers 2>/dev/null' | grep -c Running || echo "0")

if [[ "$HARBOR_READY" -gt 0 ]]; then
    print_debug "Harbor稼働中 (Running pods: $HARBOR_READY)"
    
    # Harbor LoadBalancer IP取得
    HARBOR_IP=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl -n harbor get service harbor-core -o jsonpath="{.status.loadBalancer.ingress[0].ip}"' 2>/dev/null || echo "")
    
    if [[ -z "$HARBOR_IP" ]]; then
        # LoadBalancerが利用できない場合はMetalLB IPを使用
        print_debug "LoadBalancer IPが取得できません。MetalLB IPを使用してHarborにアクセスします"
        
        # MetalLB範囲の最初のIP (192.168.122.100) を試行
        HARBOR_URL="http://192.168.122.100"
        
        # 接続テスト
        HARBOR_STATUS=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "curl -s -o /dev/null -w '%{http_code}' $HARBOR_URL/api/v2.0/systeminfo --connect-timeout 5" 2>/dev/null || echo "000")
        
        if [[ "$HARBOR_STATUS" != "200" ]]; then
            print_debug "MetalLB IP接続失敗。port-forwardを使用します"
            
            # 既存のport-forwardを停止
            ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'pkill -f "kubectl port-forward.*harbor-core" 2>/dev/null || true'
            sleep 2
            
            # バックグラウンドでport-forward開始（PIDを記録）
            ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl port-forward -n harbor svc/harbor-core 8080:80 > /dev/null 2>&1 &' &
            PORT_FORWARD_PID=$!
            sleep 5
            HARBOR_URL="http://192.168.122.10:8080"
        fi
    else
        HARBOR_URL="http://$HARBOR_IP"
    fi
    
    print_debug "Harbor URL: $HARBOR_URL"
    
    # Harbor認証情報の取得（既に設定済みの場合）
    HARBOR_USERNAME="${HARBOR_USERNAME:-admin}"
    HARBOR_PASSWORD="${HARBOR_PASSWORD:-Harbor12345}"
    
    # Harbor接続確認
    print_debug "Harbor接続確認中..."
    HARBOR_TEST=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "curl -s -o /dev/null -w '%{http_code}' '$HARBOR_URL/api/v2.0/systeminfo' --connect-timeout 10" 2>/dev/null || echo "000")
    
    if [[ "$HARBOR_TEST" == "200" ]]; then
        print_debug "Harbor接続成功"
        
        # 既存プロジェクト確認
        print_debug "既存sandboxプロジェクト確認中..."
        EXISTING_PROJECT=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "curl -s '$HARBOR_URL/api/v2.0/projects?name=sandbox' -u '$HARBOR_USERNAME:$HARBOR_PASSWORD' --connect-timeout 10" 2>/dev/null || echo "error")
        
        if [[ "$EXISTING_PROJECT" == *'"name":"sandbox"'* ]]; then
            print_debug "sandboxプロジェクトは既に存在しています"
        else
            # Harbor APIを使用してsandboxプロジェクト作成
            print_debug "sandboxプロジェクト作成中..."
            
            # プロジェクト作成APIリクエスト
            PROJECT_JSON='{
                "project_name": "sandbox",
                "public": false,
                "metadata": {
                    "public": "false"
                }
            }'
            
            # curlを使用してHarbor APIにリクエスト送信
            CREATE_RESULT=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "curl -s -X POST '$HARBOR_URL/api/v2.0/projects' \
                -H 'Content-Type: application/json' \
                -u '$HARBOR_USERNAME:$HARBOR_PASSWORD' \
                -d '$PROJECT_JSON' \
                -w '%{http_code}' \
                --connect-timeout 10" 2>/dev/null || echo "000")
            
            if [[ "$CREATE_RESULT" == *"201"* ]]; then
                print_status "✓ Harbor sandboxプロジェクト作成完了"
            elif [[ "$CREATE_RESULT" == *"409"* ]]; then
                print_debug "sandboxプロジェクトは既に存在しています"
            else
                print_warning "Harbor sandboxプロジェクト作成に失敗しました (HTTP: $CREATE_RESULT)"
                print_debug "手動で作成する場合:"
                echo "  1. Harbor UI ($HARBOR_URL) にアクセス"
                echo "  2. admin/$HARBOR_PASSWORD でログイン"
                echo "  3. Projects > NEW PROJECT > sandbox (Private) を作成"
            fi
        fi
    else
        print_warning "Harbor接続に失敗しました (HTTP: $HARBOR_TEST)"
        print_debug "手動で作成する場合:"
        echo "  1. Harbor UI ($HARBOR_URL) にアクセス"
        echo "  2. admin/$HARBOR_PASSWORD でログイン"
        echo "  3. Projects > NEW PROJECT > sandbox (Private) を作成"
    fi
    
    # port-forwardプロセスを適切に終了
    if [[ -z "$HARBOR_IP" ]] && [[ "$HARBOR_STATUS" != "200" ]]; then
        print_debug "port-forwardプロセスを停止中..."
        
        # ローカルのport-forwardプロセスを停止
        if [[ -n "${PORT_FORWARD_PID:-}" ]]; then
            kill $PORT_FORWARD_PID 2>/dev/null || true
            wait $PORT_FORWARD_PID 2>/dev/null || true
        fi
        
        # リモートのport-forwardプロセスも停止
        ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'pkill -f "kubectl port-forward.*harbor-core" 2>/dev/null || true'
        sleep 1
    fi
    
else
    print_warning "Harborがまだ稼働していません"
    print_debug "ArgoCD App of Appsでのデプロイ完了後に以下を手動実行してください："
    echo "  1. Harbor UI (http://192.168.122.100) にアクセス"
    echo "  2. admin/Harbor12345 でログイン"
    echo "  3. Projects > NEW PROJECT > sandbox (Private) を作成"
fi

# 11. Kubernetes sandboxネームスペース作成
print_status "=== Phase 4.11: Kubernetes sandboxネームスペース作成 ==="
print_debug "Kubernetesクラスタ内にsandboxネームスペースを作成します"

# sandboxネームスペース作成
if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl create namespace sandbox" 2>/dev/null; then
    print_status "✓ Kubernetes sandboxネームスペース作成完了"
else
    # 既存チェック
    if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl get namespace sandbox" >/dev/null 2>&1; then
        print_debug "sandboxネームスペースは既に存在しています"
    else
        print_warning "sandboxネームスペース作成に失敗しました"
        print_debug "手動で作成する場合:"
        echo "  kubectl create namespace sandbox"
    fi
fi

# sandboxネームスペース確認
SANDBOX_NS_STATUS=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl get namespace sandbox -o jsonpath='{.status.phase}'" 2>/dev/null || echo "NotFound")
if [[ "$SANDBOX_NS_STATUS" == "Active" ]]; then
    print_debug "sandboxネームスペースは正常に稼働中です"
else
    print_warning "sandboxネームスペースの状態が確認できません: $SANDBOX_NS_STATUS"
fi

# Slack Secret作成（sandbox namespace用）
print_status "=== Slack Secret作成 ==="
print_debug "External Secretsを使用してSlack secret作成中..."

# sandbox namespaceが存在することを確認
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl create namespace sandbox --dry-run=client -o yaml | kubectl apply -f -' >/dev/null 2>&1

# Pulumi Access Token確認
if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret pulumi-access-token -n external-secrets-system' >/dev/null 2>&1; then
    print_error "Pulumi Access Token が見つかりません"
    print_error "External Secretsが利用できません。セットアップを確認してください"
    exit 1
fi

# ClusterSecretStore確認
if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get clustersecretstore pulumi-esc-store' >/dev/null 2>&1; then
    print_error "ClusterSecretStore 'pulumi-esc-store' が見つかりません"
    print_error "External Secretsセットアップが不完全です"
    exit 1
fi

# ClusterSecretStore接続確認
SECRETSTORE_STATUS=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get clustersecretstore pulumi-esc-store -o jsonpath="{.status.conditions[?(@.type==\"Ready\")].status}" 2>/dev/null' || echo "Unknown")
if [ "$SECRETSTORE_STATUS" != "True" ]; then
    print_error "ClusterSecretStore が準備できていません (Status: $SECRETSTORE_STATUS)"
    exit 1
fi

# ExternalSecretが既に存在する場合はスキップ
if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get externalsecret slack-externalsecret -n sandbox' >/dev/null 2>&1; then
    print_debug "✓ Slack ExternalSecretは既に存在します"
else
    print_debug "Slack ExternalSecretを作成中..."
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'cat > /tmp/slack-external.yaml << EOF
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: slack-externalsecret
  namespace: sandbox
spec:
  refreshInterval: 20s
  secretStoreRef:
    name: pulumi-esc-store
    kind: ClusterSecretStore
  target:
    name: slack
    creationPolicy: Owner
    template:
      type: Opaque
      engineVersion: v2
      data:
        webhook_url: "https://hooks.slack.com/services/DUMMY/DUMMY/DUMMY"
        bot_token: "xoxb-dummy-token"
        app_token: "xapp-dummy-token"
        channel: "#general"
        username: "bot"
        token: "xoxb-dummy-token"
  data:
  - secretKey: dummy
    remoteRef:
      key: harbor
EOF'
    
    if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl apply -f /tmp/slack-externalsecret.yaml'; then
        print_error "Slack ExternalSecretの作成に失敗しました"
        exit 1
    fi
    print_debug "✓ Slack ExternalSecret作成完了"
fi

# Secret作成確認と待機
print_debug "Slack secret作成待機中..."
timeout=60
while [ $timeout -gt 0 ]; do
    if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret slack -n sandbox' >/dev/null 2>&1; then
        print_debug "✓ Slack secret作成完了"
        break
    fi
    
    # ExternalSecretの状態確認
    EXTERNALSECRET_STATUS=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get externalsecret slack-externalsecret -n sandbox -o jsonpath="{.status.conditions[?(@.type==\"Ready\")].status}" 2>/dev/null' || echo "Unknown")
    if [ "$EXTERNALSECRET_STATUS" = "False" ]; then
        ERROR_MESSAGE=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get externalsecret slack-externalsecret -n sandbox -o jsonpath="{.status.conditions[?(@.type==\"Ready\")].message}" 2>/dev/null' || echo "Unknown")
        print_error "ExternalSecret エラー: $ERROR_MESSAGE"
        exit 1
    fi
    
    echo "Slack secret作成待機中... (残り ${timeout}秒) - ExternalSecret Status: $EXTERNALSECRET_STATUS"
    sleep 3
    timeout=$((timeout - 3))
done

if [ $timeout -le 0 ]; then
    print_error "Slack secretの作成がタイムアウトしました"
    print_error "詳細確認: kubectl describe externalsecret slack-externalsecret -n sandbox"
    exit 1
fi

echo ""

# 12. 構築結果確認
print_status "=== Kubernetes基盤構築結果確認 ==="

# ArgoCD状態確認
print_debug "ArgoCD状態確認..."
ARGOCD_READY=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get pods -n argocd --no-headers' | grep -c Running || echo "0")

# LoadBalancer IP取得
LB_IP=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl -n ingress-nginx get service ingress-nginx-controller -o jsonpath="{.status.loadBalancer.ingress[0].ip}"' 2>/dev/null || echo "pending")

print_status "=== 構築完了サマリー ==="
echo ""
echo "=== インフラコンポーネント状態 ==="
echo "ArgoCD: $ARGOCD_READY Pod(s) Running"
echo "LoadBalancer IP: $LB_IP"
echo ""

echo "=== 次のステップ ====" 
echo "1. ArgoCD UI アクセス: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "2. ArgoCD管理者パスワード確認: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo "3. Harbor UI アクセス: kubectl port-forward svc/harbor-core -n harbor 8081:80"
echo "4. Harbor パスワード確認: kubectl get secret harbor-admin-secret -n harbor -o jsonpath='{.data.password}' | base64 -d"
echo "5. GitHub Actions設定（ARCセットアップ）:"
echo "   export GITHUB_TOKEN=YOUR_GITHUB_PERSONAL_ACCESS_TOKEN"
echo "   export GITHUB_USERNAME=YOUR_GITHUB_USERNAME"
echo "   ./setup-arc.sh"
echo "6. GitHub Actions Workflowデプロイ:"
echo "   cp automation/phase4/github-actions-example.yml .github/workflows/build-and-push.yml"
echo "   git add .github/workflows/build-and-push.yml"
echo "   git commit -m \"GitHub Actions Harbor対応ワークフロー追加\""
echo "   git push"
echo "7. GitリポジトリをCommit & Push後、ArgoCDでアプリケーションの自動デプロイを確認"
echo "8. Cloudflared Secret作成後、cloudflaredアプリケーションの同期を確認"
echo ""
echo "🔧 Harbor パスワード管理:"
echo "- パスワード更新: ./harbor-password-update.sh <新しいパスワード>"
echo "- 対話式更新: ./harbor-password-update.sh --interactive"
echo "- Secret確認: kubectl get secrets -n harbor,arc-systems,default,sandbox"
echo ""
echo "🎉 ワンショットセットアップ対応:"
echo "- Harbor パスワード: 自動でk8s Secret化済み"
echo "- GitHub Actions Ready: Secret参照方式で完全自動化"
echo "- Docker-in-Docker対応: systemd不要で確実にpush"
echo "- 証明書問題解決: Harbor IP SAN対応済み"
echo ""

# 設定情報保存
cat > phase4-info.txt << EOF
=== Phase 4 基本インフラ構築完了 (GitOps対応版) ===

構築完了コンポーネント:
- MetalLB (LoadBalancer)
- NGINX Ingress Controller  
- cert-manager
- ArgoCD: $ARGOCD_READY Pod(s) Running
- LoadBalancer IP: $LB_IP
- Harbor パスワード管理: セキュアにSecret化済み

ArgoCD App of Apps デプロイ済み:
- リポジトリ: https://github.com/ksera524/k8s_myHome.git
- 管理対象: infra/*.yaml

Harbor Secret管理:
- harbor-admin-secret (harbor namespace)
- harbor-auth (arc-systems, default namespaces)
- harbor-registry-secret (Docker認証用)
${EXTERNAL_SECRETS_ENABLED:+- External Secrets 経由でPulumi ESCから自動取得}
${EXTERNAL_SECRETS_ENABLED:-"- 手動管理モード"}

接続情報:
- k8sクラスタ: ssh k8suser@192.168.122.10
- ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443
- Harbor UI: kubectl port-forward svc/harbor-core -n harbor 8081:80
- LoadBalancer経由: http://$LB_IP (Ingressルーティング)

手動セットアップ必要項目:
1. Cloudflared Secret作成
2. GitHub Repository Secrets設定:
   - HARBOR_USERNAME: ${HARBOR_USERNAME:-admin}
   - HARBOR_PASSWORD: (設定済みパスワード)

Harbor パスワード管理コマンド:
$(if [ "$EXTERNAL_SECRETS_ENABLED" = true ]; then
    echo "- External Secrets確認: kubectl get externalsecrets -A"
    echo "- Pulumi ESC確認: kubectl get secrets -A | grep pulumi-access-token"
    echo "- Secret同期確認: kubectl describe externalsecret harbor-admin-secret -n harbor"
    echo "- Slack Secret確認: kubectl describe externalsecret slack-externalsecret -n sandbox"
else
    echo "- 更新: ./harbor-password-update.sh <新しいパスワード>"
    echo "- 対話式: ./harbor-password-update.sh --interactive"
fi)
- Secret確認: kubectl get secret harbor-admin-secret -n harbor -o yaml

External Secrets セットアップ (オプション):
- セットアップ: cd external-secrets && ./setup-external-secrets.sh
- PAT設定: ./setup-pulumi-pat.sh --interactive
- 動作確認: ./test-harbor-secrets.sh
- Slack Secret確認: kubectl get secret slack -n sandbox
EOF

# 7. ArgoCD同期待機とHarbor確認
print_status "=== Phase 4.10: ArgoCD同期とHarborデプロイ確認 ==="
print_debug "ArgoCD App of AppsによるHarborデプロイを確認します"

ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
echo "ArgoCD Applicationの同期状況確認中..."
kubectl get applications -n argocd

echo -e "\nHarbor namespace確認中..."
if kubectl get namespace harbor >/dev/null 2>&1; then
    echo "✓ Harbor namespaceが存在します"
    echo "Harbor ポッド状況:"
    kubectl get pods -n harbor 2>/dev/null || echo "Harborポッドはまだ作成されていません"
else
    echo "⚠️ Harbor namespaceがまだ作成されていません"
    echo "ArgoCD App of Appsの同期を待機してください"
fi
EOF

print_status "✓ ArgoCD同期状況確認完了"

# 13. Harbor証明書修正とIngress設定の自動適用
print_status "=== Phase 4.12: Harbor証明書修正とIngress設定の自動適用 ==="
print_debug "Harbor Docker Registry API対応とGitHub Actions対応を自動実行します"

# Harbor証明書修正スクリプトの実行
if [[ -f "$SCRIPT_DIR/harbor-cert-fix.sh" ]]; then
    print_debug "Harbor証明書修正スクリプトを実行中..."
    print_debug "- IP SAN対応Harbor証明書作成"
    print_debug "- CA信頼配布DaemonSet展開"
    print_debug "- Worker nodeのinsecure registry設定"
    print_debug "- GitHub Actions Runner再起動"
    
    # Harbor証明書修正スクリプトを実行
    if "$SCRIPT_DIR/harbor-cert-fix.sh"; then
        print_status "✓ Harbor証明書修正完了"
    else
        print_warning "Harbor証明書修正に失敗しました"
        print_debug "手動実行: cd automation/k8s-infrastructure && ./harbor-cert-fix.sh"
    fi
else
    print_warning "harbor-cert-fix.shが見つかりません"
    print_debug "Harbor証明書修正を手動実行してください"
fi

# Harbor Ingress確認
print_debug "Harbor Ingress設定を確認中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'HARBOR_INGRESS_CHECK_EOF'
# 既存のHarbor Ingressを確認
EXISTING_INGRESSES=$(kubectl get ingress -n harbor --no-headers | wc -l)
echo "Harbor Ingress数: $EXISTING_INGRESSES"

# harbor-internal-ingressが存在するか確認
if kubectl get ingress harbor-internal-ingress -n harbor >/dev/null 2>&1; then
    echo "✓ harbor-internal-ingress が存在します（Docker Registry API対応済み）"
else
    echo "⚠️ harbor-internal-ingress が見つかりません"
fi
HARBOR_INGRESS_CHECK_EOF

print_status "✓ Harbor Ingress設定確認完了"

# ARC Scale Setのinsecure registry設定の自動適用
print_debug "ARC Scale Setのinsecure registry設定を確認・修正中..."

ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'ARC_PATCH_EOF'
# 既存のARC Scale Setを確認してinsecure registry設定を適用
for runner_set in $(kubectl get AutoscalingRunnerSet -n arc-systems -o name 2>/dev/null | sed 's|.*/||'); do
    echo "ARC Scale Set '$runner_set' にinsecure registry設定を適用中..."
    
    # insecure registry設定をパッチ適用
    if kubectl patch AutoscalingRunnerSet "$runner_set" -n arc-systems \
        --type=json \
        -p='[{"op":"replace","path":"/spec/template/spec/initContainers/1/args","value":["dockerd","--host=unix:///var/run/docker.sock","--group=$(DOCKER_GROUP_GID)","--insecure-registry=192.168.122.100"]}]' 2>/dev/null; then
        echo "✓ '$runner_set' のinsecure registry設定完了"
    else
        echo "⚠️ '$runner_set' のinsecure registry設定に失敗しました（設定済みまたは存在しません）"
    fi
done

# GitHub Actions Runner Podの再起動
echo "GitHub Actions Runner Podを再起動中..."
for pod in $(kubectl get pods -n arc-systems -o name 2>/dev/null | grep runner | sed 's|.*/||'); do
    echo "ランナーポッド再起動: $pod"
    kubectl delete pod "$pod" -n arc-systems 2>/dev/null || echo "ポッド削除失敗: $pod"
done

echo "新しいランナーポッドの起動を待機中..."
sleep 15
ARC_PATCH_EOF

print_status "✓ ARC Scale Set insecure registry設定完了"

# Docker login動作確認
print_debug "Harbor Docker login動作確認中..."
DOCKER_LOGIN_TEST=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
    "docker login 192.168.122.100 -u ${HARBOR_USERNAME:-admin} -p ${HARBOR_PASSWORD:-Harbor12345} 2>&1" || echo "login_failed")

if [[ "$DOCKER_LOGIN_TEST" == *"Login Succeeded"* ]]; then
    print_status "✓ Harbor Docker login動作確認完了"
else
    print_warning "Harbor Docker login確認に失敗しました"
    print_debug "GitHub Actions実行時に認証エラーが発生する可能性があります"
fi

print_status "✓ Harbor証明書修正とIngress設定の自動適用完了"

# 14. Harbor HTTP設定の自動適用
print_status "=== Phase 4.13: Harbor HTTP設定の自動適用 ==="
print_debug "Harbor Docker push用のHTTP設定を自動適用します"

# Harbor Core ConfigMap修正
print_debug "Harbor Core ConfigMapのEXT_ENDPOINTをHTTPに修正中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'HARBOR_HTTP_CONFIG_EOF'
# Harbor Core ConfigMapをHTTP設定に修正
kubectl patch configmap harbor-core -n harbor --type merge -p '{"data":{"EXT_ENDPOINT":"http://192.168.122.100"}}'

# Harbor Core Pod再起動で設定反映
echo "Harbor Core Pod再起動中..."
kubectl delete pod -n harbor -l app=harbor,component=core 2>/dev/null || echo "Harbor Core Pod未発見"
kubectl wait --for=condition=ready pod -l app=harbor,component=core -n harbor --timeout=120s

# Harbor HTTP接続確認
echo "Harbor HTTP接続確認中..."
HTTP_TEST=$(curl -s -o /dev/null -w '%{http_code}' http://192.168.122.100/v2/ --connect-timeout 10 || echo "000")
if [[ "$HTTP_TEST" == "401" ]]; then
    echo "✓ Harbor HTTP API接続正常（401 Unauthorized - 認証待ち）"
else
    echo "⚠️ Harbor HTTP API接続異常（HTTP: $HTTP_TEST）"
fi

# Harbor HTTP認証realmを確認
REALM_TEST=$(curl -s -I http://192.168.122.100/v2/ | grep -i "www-authenticate" | grep -o 'realm="[^"]*"' || echo "")
if [[ "$REALM_TEST" == *"http://192.168.122.100"* ]]; then
    echo "✓ Harbor HTTP認証realm設定正常"
else
    echo "⚠️ Harbor HTTP認証realm設定要確認: $REALM_TEST"
fi
HARBOR_HTTP_CONFIG_EOF

print_status "✓ Harbor HTTP設定の自動適用完了"

# 15. GitHub Actions Runner insecure registry設定の自動適用
print_status "=== Phase 4.14: GitHub Actions Runner insecure registry設定の自動適用 ==="
print_debug "GitHub Actions RunnerのDocker daemon insecure registry設定を自動適用します"

# GitHub Actions Runner存在確認と設定適用
print_debug "GitHub Actions Runner設定確認・修正中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'ARC_INSECURE_REGISTRY_EOF'
# AutoscalingRunnerSet存在確認
RUNNER_SETS=$(kubectl get AutoscalingRunnerSet -n arc-systems -o name 2>/dev/null | wc -l)
if [[ "$RUNNER_SETS" -gt 0 ]]; then
    echo "GitHub Actions Runner設定を修正中..."
    
    # 各AutoscalingRunnerSetにinsecure registry設定を適用
    for runner_set in $(kubectl get AutoscalingRunnerSet -n arc-systems -o name 2>/dev/null | sed 's|.*/||'); do
        echo "Runner Set '$runner_set' にinsecure registry設定を適用中..."
        
        # dind initContainer にinsecure registry設定を追加
        if kubectl patch AutoscalingRunnerSet "$runner_set" -n arc-systems \
            --type=json \
            -p='[{"op":"replace","path":"/spec/template/spec/initContainers/1/args","value":["dockerd","--host=unix:///var/run/docker.sock","--group=$(DOCKER_GROUP_GID)","--insecure-registry=192.168.122.100"]}]' 2>/dev/null; then
            echo "✓ '$runner_set' のinsecure registry設定完了"
            
            # Runner Pod再起動で設定反映
            echo "Runner Pod再起動中..."
            kubectl delete pod -n arc-systems -l app.kubernetes.io/name="$runner_set" 2>/dev/null || echo "Runner Pod未発見"
            sleep 10
            
            # 設定反映確認
            NEW_PODS=$(kubectl get pods -n arc-systems -l app.kubernetes.io/name="$runner_set" --no-headers 2>/dev/null | wc -l)
            if [[ "$NEW_PODS" -gt 0 ]]; then
                echo "✓ '$runner_set' Runner Pod再起動完了"
            else
                echo "⚠️ '$runner_set' Runner Pod再起動要確認"
            fi
        else
            echo "⚠️ '$runner_set' のinsecure registry設定に失敗しました"
        fi
    done
else
    echo "GitHub Actions Runnerが設定されていません（後で設定時に自動適用されます）"
fi
ARC_INSECURE_REGISTRY_EOF

print_status "✓ GitHub Actions Runner insecure registry設定の自動適用完了"

print_status "Phase 4 基本インフラ構築が完了しました！"
print_debug "構築情報: phase4-info.txt"