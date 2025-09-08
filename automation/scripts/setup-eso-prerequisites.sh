#!/bin/bash
# ESO Prerequisites Setup Script
# External Secrets OperatorがPulumi ESCにアクセスするために必要な
# Pulumi Access TokenをKubernetes Secretとして事前に作成

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-logging.sh"
source "$SCRIPT_DIR/common-ssh.sh"

# 設定ファイルを読み込む
if [[ -f "$SCRIPT_DIR/../settings.toml" ]]; then
    log_status "settings.tomlから設定を読み込み中..."
    source "$SCRIPT_DIR/settings-loader.sh" load 2>/dev/null || true
else
    log_error "settings.tomlが見つかりません"
    log_error "automation/settings.tomlを作成してください"
    exit 1
fi

# Pulumi Access Tokenの確認
check_pulumi_token() {
    if [[ -z "${PULUMI_ACCESS_TOKEN:-}" ]]; then
        log_error "PULUMI_ACCESS_TOKENが設定されていません"
        log_error "config/secrets/.envファイルに以下を設定してください："
        log_error "PULUMI_ACCESS_TOKEN=pul-xxxxxxxxxxxxxxxx"
        exit 1
    fi
    log_success "✓ Pulumi Access Token確認済み"
}

# External Secrets namespace作成
create_eso_namespace() {
    log_status "External Secrets namespaceを作成中..."
    k8s_kubectl "create namespace external-secrets-system --dry-run=client -o yaml | kubectl apply -f -"
    log_success "✓ Namespace作成完了"
}

# Pulumi ESC token Secret作成
create_pulumi_token_secret() {
    log_status "Pulumi ESC token Secretを作成中..."
    
    # 既存のSecretを削除（もし存在すれば）
    k8s_kubectl "delete secret pulumi-esc-token -n external-secrets-system --ignore-not-found"
    
    # 新しいSecretを作成
    k8s_kubectl "create secret generic pulumi-esc-token \
        --from-literal=accessToken='${PULUMI_ACCESS_TOKEN}' \
        -n external-secrets-system"
    
    log_success "✓ Pulumi ESC token Secret作成完了"
    
    # 確認
    k8s_kubectl "get secret pulumi-esc-token -n external-secrets-system"
}

# ServiceAccountの権限設定
setup_rbac() {
    log_status "RBAC設定を適用中..."
    
    k8s_kubectl "apply -f -" << 'EOF'
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
EOF
    
    log_success "✓ RBAC設定完了"
}

# メイン処理
main() {
    log_status "=== ESO Prerequisites Setup開始 ==="
    
    check_pulumi_token
    create_eso_namespace
    create_pulumi_token_secret
    setup_rbac
    
    log_success "=== ESO Prerequisites Setup完了 ==="
    log_status "External Secrets OperatorがPulumi ESCにアクセスする準備が整いました"
}

# スクリプトが直接実行された場合
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi