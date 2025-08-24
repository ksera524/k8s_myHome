#!/bin/bash
# Bootstrap Secrets Setup Script
# 環境変数から初期シークレットを作成し、ESOが参照できるようにする

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-colors.sh"
source "$SCRIPT_DIR/common-ssh.sh"

# 環境変数を読み込む
if [[ -f "$SCRIPT_DIR/../../config/secrets/.env" ]]; then
    print_status "環境変数を読み込み中..."
    source "$SCRIPT_DIR/../../config/secrets/.env"
else
    print_error ".envファイルが見つかりません"
    exit 1
fi

# Bootstrap namespace作成
create_bootstrap_namespace() {
    print_status "bootstrap namespaceを作成中..."
    k8s_kubectl "create namespace bootstrap --dry-run=client -o yaml | kubectl apply -f -"
}

# Bootstrap Secretsの作成
create_bootstrap_secrets() {
    print_status "Bootstrap Secretsを作成中..."
    
    # GitHub Token
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        k8s_kubectl "create secret generic github-bootstrap \
            --from-literal=token='${GITHUB_TOKEN}' \
            --from-literal=pat='${GITHUB_TOKEN}' \
            -n bootstrap --dry-run=client -o yaml | kubectl apply -f -"
        print_success "✓ GitHub Bootstrap Secret作成完了"
    else
        print_warning "GITHUB_TOKENが設定されていません"
    fi
    
    # Harbor Credentials
    if [[ -n "${HARBOR_ADMIN_PASSWORD:-}" ]]; then
        k8s_kubectl "create secret generic harbor-bootstrap \
            --from-literal=admin_password='${HARBOR_ADMIN_PASSWORD}' \
            --from-literal=ci_password='${HARBOR_ADMIN_PASSWORD}' \
            --from-literal=url='192.168.122.100' \
            --from-literal=username='admin' \
            -n bootstrap --dry-run=client -o yaml | kubectl apply -f -"
        print_success "✓ Harbor Bootstrap Secret作成完了"
    else
        print_warning "HARBOR_ADMIN_PASSWORDが設定されていません"
    fi
    
    # Cloudflared Token
    if [[ -n "${CLOUDFLARED_TOKEN:-}" ]]; then
        k8s_kubectl "create secret generic cloudflared-bootstrap \
            --from-literal=token='${CLOUDFLARED_TOKEN}' \
            -n bootstrap --dry-run=client -o yaml | kubectl apply -f -"
        print_success "✓ Cloudflared Bootstrap Secret作成完了"
    else
        print_warning "CLOUDFLARED_TOKENが設定されていません"
    fi
    
    # Slack Token
    if [[ -n "${SLACK_TOKEN:-}" ]]; then
        k8s_kubectl "create secret generic slack-bootstrap \
            --from-literal=token='${SLACK_TOKEN}' \
            -n bootstrap --dry-run=client -o yaml | kubectl apply -f -"
        print_success "✓ Slack Bootstrap Secret作成完了"
    else
        print_warning "SLACK_TOKENが設定されていません"
    fi
    
    # ArgoCD GitHub OAuth
    if [[ -n "${ARGOCD_GITHUB_CLIENT_ID:-}" ]] && [[ -n "${ARGOCD_GITHUB_CLIENT_SECRET:-}" ]]; then
        k8s_kubectl "create secret generic argocd-github-oauth-bootstrap \
            --from-literal=client-id='${ARGOCD_GITHUB_CLIENT_ID}' \
            --from-literal=client-secret='${ARGOCD_GITHUB_CLIENT_SECRET}' \
            -n bootstrap --dry-run=client -o yaml | kubectl apply -f -"
        print_success "✓ ArgoCD GitHub OAuth Bootstrap Secret作成完了"
    else
        print_warning "ArgoCD GitHub OAuth認証情報が設定されていません"
    fi
}

# メイン処理
main() {
    print_status "=== Bootstrap Secrets Setup開始 ==="
    
    create_bootstrap_namespace
    create_bootstrap_secrets
    
    print_success "=== Bootstrap Secrets Setup完了 ==="
}

# 実行
main "$@"