#!/bin/bash

# 共通Kubernetes操作ライブラリ
# Harbor認証設定など類似処理の統合

set -euo pipefail

# 共通設定読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-colors.sh"

# =============================================================================
# Harbor認証関連共通関数
# =============================================================================

# Harbor認証情報をESO管理のK8s Secretから取得
get_harbor_credentials() {
    local namespace="${1:-arc-systems}"
    local secret_name="${2:-harbor-auth}"
    
    print_debug "Harbor認証情報をK8s Secret($namespace/$secret_name)から取得中..."
    
    if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl get secret $secret_name -n $namespace" >/dev/null 2>&1; then
        print_debug "ESO管理のHarbor認証情報を取得中..."
        
        HARBOR_USERNAME=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
            "kubectl get secret $secret_name -n $namespace -o jsonpath='{.data.HARBOR_USERNAME}' | base64 -d" 2>/dev/null)
        HARBOR_PASSWORD=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
            "kubectl get secret $secret_name -n $namespace -o jsonpath='{.data.HARBOR_PASSWORD}' | base64 -d" 2>/dev/null)
        
        if [[ -n "$HARBOR_USERNAME" && -n "$HARBOR_PASSWORD" ]]; then
            export HARBOR_USERNAME
            export HARBOR_PASSWORD
            print_status "✓ ESO管理のHarbor認証情報取得完了"
            print_debug "HARBOR_USERNAME: $HARBOR_USERNAME"
            print_debug "HARBOR_PASSWORD: ${HARBOR_PASSWORD:0:3}... (先頭3文字のみ表示)"
            return 0
        else
            print_error "K8s SecretからのHarbor認証情報取得に失敗"
            return 1
        fi
    else
        print_warning "$secret_name Secret ($namespace) が見つかりません"
        return 1
    fi
}

# GitHub認証情報をESO管理のK8s Secretから取得
get_github_credentials() {
    local namespace="${1:-arc-systems}"
    local secret_name="${2:-github-auth}"
    
    print_debug "GitHub認証情報をK8s Secret($namespace/$secret_name)から取得中..."
    
    if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl get secret $secret_name -n $namespace" >/dev/null 2>&1; then
        print_debug "ESO管理のGitHub認証情報を取得中..."
        
        GITHUB_TOKEN=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
            "kubectl get secret $secret_name -n $namespace -o jsonpath='{.data.GITHUB_TOKEN}' | base64 -d" 2>/dev/null)
        GITHUB_USERNAME=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
            "kubectl get secret $secret_name -n $namespace -o jsonpath='{.data.GITHUB_USERNAME}' | base64 -d" 2>/dev/null)
        
        if [[ -n "$GITHUB_TOKEN" && -n "$GITHUB_USERNAME" ]]; then
            export GITHUB_TOKEN
            export GITHUB_USERNAME
            print_status "✓ ESO管理のGitHub認証情報取得完了"
            print_debug "GITHUB_USERNAME: $GITHUB_USERNAME"
            print_debug "GITHUB_TOKEN: ${GITHUB_TOKEN:0:8}... (先頭8文字のみ表示)"
            return 0
        else
            print_error "K8s SecretからのGitHub認証情報取得に失敗"
            return 1
        fi
    else
        print_warning "$secret_name Secret ($namespace) が見つかりません"
        return 1
    fi
}

# =============================================================================
# Kubernetes操作共通関数
# =============================================================================

# ArgoCD Application同期ステータス確認
check_argocd_app_sync() {
    local app_name="$1"
    local namespace="${2:-argocd}"
    
    print_debug "$app_name アプリケーションの同期状態確認中..."
    
    local sync_status=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
        "kubectl get application $app_name -n $namespace -o jsonpath='{.status.sync.status}'" 2>/dev/null)
    
    if [[ "$sync_status" == "Synced" ]]; then
        print_status "✓ $app_name: 同期済み"
        return 0
    else
        print_warning "$app_name: 同期状態 = $sync_status"
        return 1
    fi
}

# ArgoCD Application強制同期
force_sync_argocd_app() {
    local app_name="$1"
    local namespace="${2:-argocd}"
    
    print_debug "$app_name アプリケーション強制同期中..."
    
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
        "kubectl annotate application $app_name -n $namespace argocd.argoproj.io/refresh=now --overwrite" >/dev/null
    
    print_status "✓ $app_name: 強制同期実行完了"
}

# ExternalSecret同期ステータス確認
check_external_secret_sync() {
    local secret_name="$1"
    local namespace="$2"
    
    print_debug "$secret_name ExternalSecret同期状態確認中..."
    
    local status=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
        "kubectl get externalsecret $secret_name -n $namespace -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" 2>/dev/null)
    
    if [[ "$status" == "True" ]]; then
        print_status "✓ $secret_name: ExternalSecret同期済み"
        return 0
    else
        print_warning "$secret_name: ExternalSecret同期状態 = $status"
        return 1
    fi
}

# Kubernetes Secret存在確認
check_k8s_secret_exists() {
    local secret_name="$1"
    local namespace="$2"
    
    if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
        "kubectl get secret $secret_name -n $namespace" >/dev/null 2>&1; then
        print_debug "✓ K8s Secret $secret_name ($namespace) 存在確認"
        return 0
    else
        print_debug "✗ K8s Secret $secret_name ($namespace) が見つかりません"
        return 1
    fi
}

# =============================================================================
# 統合された設定確認関数
# =============================================================================

# Harbor設定の完全性確認
validate_harbor_setup() {
    print_status "Harbor設定の完全性確認中..."
    
    # 1. Harbor Namespace確認
    if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get namespace harbor' >/dev/null 2>&1; then
        print_error "Harbor namespaceが見つかりません"
        return 1
    fi
    
    # 2. Harbor Pod稼働確認
    local ready_pods=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
        'kubectl get pods -n harbor --no-headers | grep Running | wc -l')
    
    if [[ "$ready_pods" -gt 0 ]]; then
        print_status "✓ Harbor Pods稼働中: $ready_pods pods"
    else
        print_warning "Harbor Podsが稼働していません"
        return 1
    fi
    
    # 3. Harbor認証情報確認
    if get_harbor_credentials; then
        print_status "✓ Harbor認証情報取得成功"
    else
        print_error "Harbor認証情報取得失敗"
        return 1
    fi
    
    print_status "✓ Harbor設定完全性確認完了"
    return 0
}

# External Secrets Operator設定確認
validate_eso_setup() {
    print_status "External Secrets Operator設定確認中..."
    
    # 1. ESO Namespace確認
    if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get namespace external-secrets-system' >/dev/null 2>&1; then
        print_error "external-secrets-system namespaceが見つかりません"
        return 1
    fi
    
    # 2. ESO Pod稼働確認
    local eso_ready=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
        'kubectl get pods -n external-secrets-system --no-headers | grep Running | wc -l')
    
    if [[ "$eso_ready" -gt 0 ]]; then
        print_status "✓ External Secrets Operator稼働中: $eso_ready pods"
    else
        print_error "External Secrets Operatorが稼働していません"
        return 1
    fi
    
    # 3. ClusterSecretStore確認
    if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
        'kubectl get clustersecretstore pulumi-esc-store' >/dev/null 2>&1; then
        print_status "✓ ClusterSecretStore (pulumi-esc-store) 存在確認"
    else
        print_error "ClusterSecretStore (pulumi-esc-store) が見つかりません"
        return 1
    fi
    
    print_status "✓ External Secrets Operator設定確認完了"
    return 0
}

print_debug "共通K8sユーティリティライブラリ読み込み完了"