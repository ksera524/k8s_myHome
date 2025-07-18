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

# 0. 前提条件確認
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
cat <<EOL | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.122.100-192.168.122.150
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
EOL

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
cat <<EOL | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-cluster-issuer
spec:
  selfSigned: {}
EOL

echo "✓ cert-manager設定完了"
EOF

print_status "✓ cert-manager インストール完了"

# 4. StorageClass設定
print_status "=== Phase 4.4: StorageClass設定 ==="
print_debug "永続ストレージ機能を設定します"

ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
# Local StorageClass作成
cat <<EOL | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
EOL

echo "✓ StorageClass設定完了"

# Harbor用PersistentVolume事前作成
echo "Harbor用PersistentVolume作成中..."

# 必要なディレクトリを作成
echo "Harbor用ディレクトリを作成中..."
sudo mkdir -p /tmp/harbor-jobservice && sudo chmod 777 /tmp/harbor-jobservice

# Harbor jobservice用PV作成
cat <<EOL | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: harbor-jobservice-pv-new
spec:
  capacity:
    storage: 1Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /tmp/harbor-jobservice
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - k8s-control-plane-1
EOL

echo "✓ Harbor用PersistentVolume作成完了"
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
cat <<EOL | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
  - host: argocd.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
EOL

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

# Harbor パスワード管理スクリプトの実行
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/harbor-password-manager.sh" ]]; then
    print_debug "Harbor パスワード管理スクリプトを実行中..."
    print_debug "このスクリプトはHarborパスワードを安全にk8s Secretとして保存します"
    
    # Harbor パスワード管理スクリプトを実行
    bash "$SCRIPT_DIR/harbor-password-manager.sh"
    
    # スクリプト実行結果からパスワードを取得
    HARBOR_PASSWORD=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
        'kubectl get secret harbor-admin-secret -n harbor -o jsonpath="{.data.password}" | base64 -d' 2>/dev/null || echo "Harbor12345")
    HARBOR_USERNAME="admin"
    export HARBOR_PASSWORD HARBOR_USERNAME
    print_debug "✓ Harbor パスワード管理完了"
    
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
    --from-literal=HARBOR_PASSWORD="Harbor12345" \
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
    fi
else
    # フォールバック: 従来の手動入力方式
    print_warning "harbor-password-manager.sh が見つかりません、手動入力します"
    echo ""
    print_status "Harbor管理者パスワードを設定してください"
    echo "デフォルトのパスワード（Harbor12345）を使用する場合は、空エンターを押してください"
    echo -n "Harbor管理者パスワード [Harbor12345]: "
    read -s HARBOR_PASSWORD_INPUT
    echo ""

    if [[ -n "$HARBOR_PASSWORD_INPUT" ]]; then
        export HARBOR_PASSWORD="$HARBOR_PASSWORD_INPUT"
        print_debug "✓ Harborパスワード設定完了"
    else
        export HARBOR_PASSWORD="Harbor12345"
        print_debug "デフォルトパスワード（Harbor12345）を使用します"
    fi
    export HARBOR_USERNAME="admin"
    
    # 手動入力の場合もSecret作成
    print_debug "手動入力パスワードでSecret作成中..."
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << EOF
# Harbor namespace作成（まだ存在しない場合）
kubectl create namespace harbor --dry-run=client -o yaml | kubectl apply -f -

# Harbor管理者パスワードSecret作成/更新
kubectl create secret generic harbor-admin-secret \
    --from-literal=username="$HARBOR_USERNAME" \
    --from-literal=password="$HARBOR_PASSWORD" \
    --namespace=harbor \
    --dry-run=client -o yaml | kubectl apply -f -

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
kubectl apply -f - <<'APPOFAPPS'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infrastructure
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/ksera524/k8s_myHome.git
    targetRevision: HEAD
    path: infra
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
APPOFAPPS

echo "✓ App of Apps デプロイ完了"
EOF

print_status "✓ GitOps セットアップ完了"

# 7.5. Harbor アプリケーション同期
print_status "=== Phase 4.7.5: Harbor アプリケーション同期 ==="
print_debug "Harbor パスワード設定をArgoCD経由で反映します"

ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
# ArgoCD Harbor アプリケーションの存在確認と同期
echo "Harbor アプリケーション作成を待機中..."
for i in {1..30}; do
    if kubectl get application harbor -n argocd >/dev/null 2>&1; then
        echo "✓ Harbor アプリケーションが作成されました"
        break
    fi
    echo "待機中... ($i/30)"
    sleep 10
done

# Harbor アプリケーションの強制同期でSecret設定を反映
if kubectl get application harbor -n argocd >/dev/null 2>&1; then
    echo "Harbor アプリケーション強制同期を実行中..."
    kubectl patch application harbor -n argocd --type merge -p '{"operation":{"sync":{"syncStrategy":{"hook":{"force":true}}}}}'
    
    # 同期完了待機
    echo "Harbor アプリケーション同期完了を待機中..."
    for i in {1..30}; do
        SYNC_STATUS=$(kubectl get application harbor -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        if [[ "$SYNC_STATUS" == "Synced" ]]; then
            echo "✓ Harbor アプリケーション同期完了"
            break
        fi
        echo "同期中... ($i/30) Status: $SYNC_STATUS"
        sleep 10
    done
    
    # Harbor jobservice Pod再起動（PV問題解決）
    echo "Harbor jobservice Pod再起動中..."
    kubectl delete pod -n harbor -l app=harbor,component=jobservice 2>/dev/null || echo "Harbor jobservice Pod未発見"
    sleep 5
    
    echo "✓ Harbor アプリケーション同期処理完了"
else
    echo "⚠️ Harbor アプリケーションの作成タイムアウト"
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
    
    # GitHub認証情報を取得（保存済みを利用または新規入力）
    if ! get_github_credentials; then
        print_warning "GitHub認証情報の取得に失敗しました"
        print_debug "ARCセットアップをスキップします"
    fi
    
    # Harbor認証情報の対話式確認
    if [[ -z "${HARBOR_USERNAME:-}" ]] || [[ -z "${HARBOR_PASSWORD:-}" ]]; then
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
print_debug "Cloudflare Tunnel用のSecret作成を行います"

# Cloudflaredトークンの入力
echo ""
print_status "Cloudflared Token設定"
echo "Cloudflare Tunnelのトークンを入力してください"
echo "取得方法: https://one.dash.cloudflare.com/ > Access > Tunnels > Create Tunnel"
echo "スキップしたい場合は空エンターを押してください"
echo ""

read -s -p "Cloudflared Token (空でスキップ): " CLOUDFLARED_TOKEN
echo ""

if [[ -n "$CLOUDFLARED_TOKEN" ]]; then
    print_debug "Cloudflared namespaceを作成中..."
    
    # Cloudflared namespace作成
    if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl create namespace cloudflared" 2>/dev/null; then
        print_debug "✓ Cloudflared namespace作成完了"
    else
        print_debug "Cloudflared namespaceは既に存在しています"
    fi
    
    # Cloudflared Secret作成
    print_debug "Cloudflared Secret作成中..."
    if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl create secret generic cloudflared --from-literal=token='$CLOUDFLARED_TOKEN' --namespace=cloudflared" 2>/dev/null; then
        print_status "✓ Cloudflared Secret作成完了"
    else
        print_warning "Cloudflared Secretは既に存在しているか、作成に失敗しました"
        print_debug "手動で更新する場合:"
        echo "  kubectl delete secret cloudflared -n cloudflared"
        echo "  kubectl create secret generic cloudflared --from-literal=token='YOUR_TOKEN' --namespace=cloudflared"
    fi
else
    print_warning "Cloudflared Tokenが入力されませんでした"
    print_warning "後で手動セットアップする場合："
    echo "  kubectl create namespace cloudflared"
    echo "  kubectl create secret generic cloudflared --from-literal=token='YOUR_TOKEN' --namespace=cloudflared"
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

echo ""

# 12. 構築結果確認
print_status "=== Kubernetes基盤構築結果確認 ==="

# ArgoCD状態確認
print_debug "ArgoCD状態確認..."
ARGOCD_READY=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get pods -n argocd --no-headers' | grep -c Running || echo "0")

# LoadBalancer IP取得
LB_IP=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl -n ingress-nginx get service ingress-nginx-controller -o jsonpath="{.status.loadBalancer.ingress[0].ip}"' 2>/dev/null || echo "pending")

# Harbor管理者パスワード取得
HARBOR_PASSWORD=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret harbor-admin-secret -n harbor -o jsonpath="{.data.password}" | base64 -d' 2>/dev/null || echo "Harbor12345")

print_status "=== 構築完了サマリー ==="
echo ""
echo "=== インフラコンポーネント状態 ==="
echo "ArgoCD: $ARGOCD_READY Pod(s) Running"
echo "LoadBalancer IP: $LB_IP"
echo "Harbor管理者パスワード: $HARBOR_PASSWORD"
echo ""

echo "=== 次のステップ ====" 
echo "1. ArgoCD UI アクセス: http://argocd.local (LoadBalancer経由) または http://$LB_IP"
echo "2. ArgoCD管理者パスワード確認: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo "3. Harbor UI アクセス: http://$LB_IP (LoadBalancer経由)"
echo "4. Harbor ログイン: admin / $HARBOR_PASSWORD"
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
echo "- Secret確認: kubectl get secrets -n harbor,arc-systems,default | grep harbor"
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
- 更新: ./harbor-password-update.sh <新しいパスワード>
- 対話式: ./harbor-password-update.sh --interactive
- Secret確認: kubectl get secret harbor-admin-secret -n harbor -o yaml
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

# Harbor HTTP Ingress設定の修正
print_debug "Harbor HTTP Ingress設定を修正中..."
print_debug "- /v2/ パスをharbor-coreサービス経由に設定"
print_debug "- Docker Registry API認証を正常化"

ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl apply -f -' << 'HARBOR_INGRESS_EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: harbor-http-ingress
  namespace: harbor
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - backend:
          service:
            name: harbor-core
            port:
              number: 80
        path: /api/
        pathType: Prefix
      - backend:
          service:
            name: harbor-core
            port:
              number: 80
        path: /service/
        pathType: Prefix
      - backend:
          service:
            name: harbor-core
            port:
              number: 80
        path: /v2/
        pathType: Prefix
      - backend:
          service:
            name: harbor-core
            port:
              number: 80
        path: /chartrepo/
        pathType: Prefix
      - backend:
          service:
            name: harbor-core
            port:
              number: 80
        path: /c/
        pathType: Prefix
      - backend:
          service:
            name: harbor-portal
            port:
              number: 80
        path: /
        pathType: Prefix
HARBOR_INGRESS_EOF

print_status "✓ Harbor HTTP Ingress設定完了"

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

print_status "Phase 4 基本インフラ構築が完了しました！"
print_debug "構築情報: phase4-info.txt"