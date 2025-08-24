#!/bin/bash

# Kubernetes基盤構築スクリプト - リファクタリング版
# MetalLB + Ingress Controller + cert-manager + ArgoCD → ESO → Harbor

set -euo pipefail

# 非対話モード設定
export DEBIAN_FRONTEND=noninteractive
export NON_INTERACTIVE=true

# スクリプトディレクトリの取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="$SCRIPT_DIR/../scripts"

# 共通関数の読み込み
source "$COMMON_DIR/common-colors.sh"
source "$COMMON_DIR/common-ssh.sh"
source "$COMMON_DIR/common-sudo.sh"
source "$COMMON_DIR/common-validation.sh"
source "$COMMON_DIR/settings-loader.sh" load 2>/dev/null || true
source "$COMMON_DIR/argocd/github-auth-utils.sh"

# 設定ファイルの読み込み
if [[ -f "$SCRIPT_DIR/../../config/config-loader.sh" ]]; then
    source "$SCRIPT_DIR/../../config/config-loader.sh"
    export_all_configs
fi

print_status "=== Kubernetes基盤構築開始（リファクタリング版） ==="

# マニフェストファイルのリスト定義
declare -A MANIFEST_FILES=(
    ["metallb-ipaddress-pool.yaml"]="../../manifests/infrastructure/networking/metallb/"
    ["cert-manager-selfsigned-issuer.yaml"]="../../manifests/infrastructure/security/cert-manager/"
    ["local-storage-class.yaml"]="../../manifests/core/storage-classes/"
    ["argocd-ingress.yaml"]="$SCRIPT_DIR/../templates/platform/"
    ["argocd-config.yaml"]="../../manifests/infrastructure/gitops/argocd/"
    ["app-of-apps.yaml"]="../../manifests/bootstrap/"
)

# 1. マニフェストファイルの準備
prepare_manifests() {
    print_status "マニフェストファイルをリモートにコピー中..."
    
    for file in "${!MANIFEST_FILES[@]}"; do
        local src="${MANIFEST_FILES[$file]}${file}"
        if [[ -f "$src" ]]; then
            k8s_scp "$src" "/tmp/$file" || {
                print_error "Failed to copy $file"
                return 1
            }
        else
            print_warning "File not found: $src"
        fi
    done
    
    print_success "✓ マニフェストファイルコピー完了"
}

# 2. 前提条件確認
check_prerequisites() {
    print_status "前提条件を確認中..."
    
    # kubeconfigの確認
    check_kubectl_config || {
        print_error "kubectl設定が無効です"
        return 1
    }
    
    # Kubernetes API接続確認
    check_k8s_api || {
        print_error "Kubernetes APIに接続できません"
        return 1
    }
    
    # 必要な環境変数の確認
    local required_vars=(
        "PULUMI_ACCESS_TOKEN"
        "METALLB_IP_START"
        "METALLB_IP_END"
        "HARBOR_LB_IP"
        "INGRESS_LB_IP"
    )
    check_required_env "${required_vars[@]}" || return 1
    
    print_success "✓ 前提条件確認完了"
}

# 3. MetalLB構成
deploy_metallb() {
    print_status "MetalLBを構成中..."
    
    # MetalLBインストール
    k8s_kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml || return 1
    
    # MetalLB起動待機
    print_status "MetalLB Podの起動を待機中..."
    k8s_kubectl wait --namespace metallb-system \
        --for=condition=ready pod \
        --selector=app=metallb \
        --timeout=300s || return 1
    
    # IPアドレスプール設定
    k8s_kubectl apply -f /tmp/metallb-ipaddress-pool.yaml || return 1
    
    print_success "✓ MetalLB構成完了"
}

# 4. NGINX Ingress Controller構成
deploy_nginx_ingress() {
    print_status "NGINX Ingress Controllerを構成中..."
    
    # NGINX Ingress Controllerインストール
    k8s_kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/baremetal/deploy.yaml || return 1
    
    # NGINX起動待機
    print_status "NGINX Ingress Controller Podの起動を待機中..."
    k8s_kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s || return 1
    
    # サービスタイプ変更
    k8s_kubectl patch svc ingress-nginx-controller -n ingress-nginx \
        --type='json' \
        -p='[{"op": "replace", "path": "/spec/type", "value": "LoadBalancer"}]' || return 1
    
    # LoadBalancer IP割り当て確認
    print_status "LoadBalancer IPの割り当てを待機中..."
    local timeout=60
    local count=0
    while [[ $count -lt $timeout ]]; do
        local lb_ip=$(k8s_kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
        if [[ -n "$lb_ip" ]]; then
            print_success "✓ LoadBalancer IP割り当て完了: $lb_ip"
            break
        fi
        sleep 2
        ((count+=2))
    done
    
    if [[ $count -ge $timeout ]]; then
        print_error "LoadBalancer IPの割り当てがタイムアウトしました"
        return 1
    fi
}

# 5. cert-manager構成
deploy_cert_manager() {
    print_status "cert-managerを構成中..."
    
    # cert-managerインストール
    k8s_kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml || return 1
    
    # cert-manager起動待機
    print_status "cert-manager Podの起動を待機中..."
    k8s_kubectl wait --namespace cert-manager \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/instance=cert-manager \
        --timeout=300s || return 1
    
    # ClusterIssuer設定
    k8s_kubectl apply -f /tmp/cert-manager-selfsigned-issuer.yaml || return 1
    
    print_success "✓ cert-manager構成完了"
}

# 6. ArgoCD構成
deploy_argocd() {
    print_status "ArgoCDを構成中..."
    
    # namespace作成
    k8s_kubectl create namespace argocd --dry-run=client -o yaml | k8s_kubectl apply -f - || return 1
    
    # ArgoCDインストール
    k8s_kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.9.3/manifests/install.yaml || return 1
    
    # ArgoCD起動待機
    print_status "ArgoCD Podの起動を待機中..."
    k8s_kubectl wait --namespace argocd \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=argocd-server \
        --timeout=600s || return 1
    
    # 追加設定適用
    k8s_kubectl apply -f /tmp/argocd-config.yaml || return 1
    
    # ArgoCD CLI設定
    local admin_password=$(k8s_kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    print_status "ArgoCD初期パスワード: $admin_password"
    
    print_success "✓ ArgoCD構成完了"
}

# 7. External Secrets Operator構成
deploy_external_secrets() {
    print_status "External Secrets Operatorを構成中..."
    
    # Helm追加
    if ! helm repo list | grep -q external-secrets; then
        helm repo add external-secrets https://charts.external-secrets.io || return 1
    fi
    helm repo update || return 1
    
    # ESOインストール
    helm upgrade --install external-secrets \
        external-secrets/external-secrets \
        -n external-secrets \
        --create-namespace \
        --set installCRDs=true \
        --wait || return 1
    
    # Pulumi ESC SecretStore設定
    configure_pulumi_esc_secretstore || return 1
    
    print_success "✓ External Secrets Operator構成完了"
}

# 8. Harbor構成
deploy_harbor() {
    print_status "Harborを構成中..."
    
    # namespace作成
    k8s_kubectl create namespace harbor --dry-run=client -o yaml | k8s_kubectl apply -f - || return 1
    
    # Helm追加
    if ! helm repo list | grep -q harbor; then
        helm repo add harbor https://helm.goharbor.io || return 1
    fi
    helm repo update || return 1
    
    # Harborインストール
    helm upgrade --install harbor harbor/harbor \
        --namespace harbor \
        --set expose.type=loadBalancer \
        --set expose.loadBalancer.IP="${HARBOR_LB_IP}" \
        --set persistence.enabled=true \
        --set persistence.persistentVolumeClaim.registry.storageClass=local-path \
        --set persistence.persistentVolumeClaim.chartmuseum.storageClass=local-path \
        --set persistence.persistentVolumeClaim.jobservice.storageClass=local-path \
        --set persistence.persistentVolumeClaim.database.storageClass=local-path \
        --set persistence.persistentVolumeClaim.redis.storageClass=local-path \
        --set persistence.persistentVolumeClaim.trivy.storageClass=local-path \
        --wait --timeout 10m || return 1
    
    print_success "✓ Harbor構成完了"
}

# 9. GitOps初期化
initialize_gitops() {
    print_status "GitOpsを初期化中..."
    
    # App of Apps適用
    k8s_kubectl apply -f /tmp/app-of-apps.yaml || return 1
    
    # 同期待機
    print_status "ArgoCD Applicationの同期を待機中..."
    sleep 30
    
    # Application状態確認
    k8s_kubectl get applications -n argocd || true
    
    print_success "✓ GitOps初期化完了"
}

# メイン処理
main() {
    # エラーハンドリング
    trap 'print_error "エラーが発生しました: $?"' ERR
    
    # 各ステップ実行
    prepare_manifests || exit 1
    check_prerequisites || exit 1
    deploy_metallb || exit 1
    deploy_nginx_ingress || exit 1
    deploy_cert_manager || exit 1
    deploy_argocd || exit 1
    deploy_external_secrets || exit 1
    deploy_harbor || exit 1
    initialize_gitops || exit 1
    
    print_success "=== Kubernetes基盤構築完了 ==="
    
    # アクセス情報表示
    print_status "アクセス情報:"
    echo "  ArgoCD: kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "  Harbor: http://${HARBOR_LB_IP}"
    echo "  Ingress: http://${INGRESS_LB_IP}"
}

# Pulumi ESC SecretStore設定関数
configure_pulumi_esc_secretstore() {
    print_status "Pulumi ESC SecretStoreを設定中..."
    
    cat <<EOF | k8s_kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: pulumi-esc-credentials
  namespace: external-secrets
type: Opaque
stringData:
  access-token: "${PULUMI_ACCESS_TOKEN}"
---
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: pulumi-esc
spec:
  provider:
    pulumi:
      organization: "${PULUMI_ORGANIZATION:-k8s-myhome}"
      project: "${PULUMI_PROJECT:-k8s-myhome}"
      environment: "${PULUMI_ENVIRONMENT:-home}"
      accessToken:
        secretRef:
          name: pulumi-esc-credentials
          namespace: external-secrets
          key: access-token
EOF
}

# スクリプト実行
main "$@"