#!/bin/bash

# Phase 4: 基本インフラ自動構築スクリプト
# MetalLB + Ingress Controller + cert-manager + ArgoCD

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

print_status "=== Phase 4: 基本インフラ構築開始 ==="

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

# ArgoCD管理者パスワード取得・表示
echo "ArgoCD管理者パスワード:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""

# ArgoCD Ingress設定
cat <<EOL | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
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
              number: 443
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 443
EOL

echo "✓ ArgoCD Ingress設定完了"
echo "✓ ArgoCD設定完了"
EOF

print_status "✓ ArgoCD インストール完了"

# 6. App of Apps デプロイ
print_status "=== Phase 4.6: App of Apps デプロイ ==="
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

# 8. GitHub Actions Runner Controller (ARC) セットアップ
print_status "=== Phase 4.8: GitHub Actions Runner Controller (ARC) セットアップ ==="
print_debug "GitHub Actions Self-hosted Runnerをk8s上にデプロイします"

# GitHub設定の確認・入力
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/setup-arc.sh" ]]; then
    # GitHub設定の対話式確認
    if [[ -z "${GITHUB_TOKEN:-}" ]] || [[ -z "${GITHUB_USERNAME:-}" ]]; then
        echo ""
        print_status "GitHub Actions設定に必要な情報を入力してください"
        print_debug "スキップしたい場合は空エンターを押してください"
        
        # GITHUB_TOKEN入力
        if [[ -z "${GITHUB_TOKEN:-}" ]]; then
            echo "GitHub Personal Access Token (repo, workflow, admin:org権限必要):"
            echo "取得方法: https://github.com/settings/tokens"
            echo -n "GITHUB_TOKEN (空でスキップ): "
            read -s GITHUB_TOKEN_INPUT
            echo ""
            if [[ -n "$GITHUB_TOKEN_INPUT" ]]; then
                export GITHUB_TOKEN="$GITHUB_TOKEN_INPUT"
                print_debug "GITHUB_TOKEN設定完了"
            fi
        fi
        
        # GITHUB_USERNAME入力
        if [[ -z "${GITHUB_USERNAME:-}" ]]; then
            echo -n "GITHUB_USERNAME (空でスキップ): "
            read GITHUB_USERNAME_INPUT
            if [[ -n "$GITHUB_USERNAME_INPUT" ]]; then
                export GITHUB_USERNAME="$GITHUB_USERNAME_INPUT"
                print_debug "GITHUB_USERNAME設定完了: $GITHUB_USERNAME"
            fi
        fi
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
        # 環境変数を明示的に渡して実行
        GITHUB_TOKEN="$GITHUB_TOKEN" GITHUB_USERNAME="$GITHUB_USERNAME" HARBOR_USERNAME="$HARBOR_USERNAME" HARBOR_PASSWORD="$HARBOR_PASSWORD" bash "$SCRIPT_DIR/setup-arc.sh"
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

# 9. 手動セットアップが必要な項目
print_status "=== Phase 4.9: 手動セットアップ項目 ==="
print_warning "以下の項目は手動でセットアップが必要です："
echo "1. Cloudflared Secret作成:"
echo "   kubectl create namespace cloudflared"
echo "   kubectl create secret generic cloudflared --from-literal=token='YOUR_TOKEN' --namespace=cloudflared"
echo ""

# 9. 構築結果確認
print_status "=== Phase 4構築結果確認 ==="

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
echo "3. GitリポジトリをCommit & Push後、ArgoCDでアプリケーションの自動デプロイを確認"
echo "4. Cloudflared Secret作成後、cloudflaredアプリケーションの同期を確認"
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

ArgoCD App of Apps デプロイ済み:
- リポジトリ: https://github.com/ksera524/k8s_myHome.git
- 管理対象: infra/*.yaml

接続情報:
- k8sクラスタ: ssh k8suser@192.168.122.10
- ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443
- LoadBalancer経由: http://$LB_IP (Ingressルーティング)

手動セットアップ必要項目:
1. Cloudflared Secret作成
2. GitHub Actions Runner Token設定
EOF

# 7. ArgoCD同期待機とHarbor確認
print_status "=== Phase 4.7: ArgoCD同期とHarborデプロイ確認 ==="
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

print_status "Phase 4 基本インフラ構築が完了しました！"
print_debug "構築情報: phase4-info.txt"