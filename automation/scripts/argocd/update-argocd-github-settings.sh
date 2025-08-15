#!/bin/bash

# ArgoCD GitHub OAuth設定を実際のGitHub情報で更新するスクリプト

set -euo pipefail

# スクリプトディレクトリ取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 共通色設定スクリプトを読み込み
source "$SCRIPT_DIR/../common-colors.sh"

# 使用方法を表示
show_usage() {
    echo "使用方法:"
    echo "  $0 --github-org <organization-name>"
    echo "  $0 --github-user <github-username>"
    echo ""
    echo "例:"
    echo "  $0 --github-org my-company"
    echo "  $0 --github-user ksera524"
    echo ""
    echo "オプション:"
    echo "  --github-org ORG     GitHub組織名を指定"
    echo "  --github-user USER   GitHubユーザー名を指定"
    echo "  --help               この使用方法を表示"
}

# パラメータ解析
GITHUB_ORG=""
GITHUB_USER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --github-org)
            GITHUB_ORG="$2"
            shift 2
            ;;
        --github-user)
            GITHUB_USER="$2"
            shift 2
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            print_error "不明なオプション: $1"
            show_usage
            exit 1
            ;;
    esac
done

# パラメータ検証
if [[ -z "$GITHUB_ORG" && -z "$GITHUB_USER" ]]; then
    print_error "GitHub組織名またはユーザー名を指定してください"
    show_usage
    exit 1
fi

if [[ -n "$GITHUB_ORG" && -n "$GITHUB_USER" ]]; then
    print_error "GitHub組織名とユーザー名の両方は指定できません"
    show_usage
    exit 1
fi

print_status "=== ArgoCD GitHub設定更新開始 ==="

# SSH known_hosts クリーンアップ
print_debug "SSH known_hosts をクリーンアップ中..."
ssh-keygen -f "$HOME/.ssh/known_hosts" -R '192.168.122.10' 2>/dev/null || true

# k8sクラスタ接続確認
print_debug "k8sクラスタ接続を確認中..."
if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
    print_error "k8sクラスタに接続できません"
    exit 1
fi

# ArgoCD ConfigMap更新
if [[ -n "$GITHUB_ORG" ]]; then
    print_status "GitHub組織「$GITHUB_ORG」でArgoCD設定を更新中..."
    
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << EOF
# GitHub組織設定でConfigMapを更新
kubectl patch configmap argocd-cm -n argocd --type merge -p '{
  "data": {
    "url": "https://argocd.qroksera.com",
    "dex.config": "connectors:\\n- type: github\\n  id: github\\n  name: GitHub\\n  config:\\n    clientId: $GITHUB_CLIENT_ID\\n    clientSecret: \\$dex.github.clientSecret\\n    orgs:\\n    - name: $GITHUB_ORG\\n    redirectURI: https://argocd.qroksera.com/api/dex/callback"
  }
}'

# RBAC設定を組織用に更新
kubectl patch configmap argocd-rbac-cm -n argocd --type merge -p '{
  "data": {
    "policy.csv": "# GitHub組織「$GITHUB_ORG」のメンバーに管理者権限を付与\\ng, $GITHUB_ORG:admin, role:admin\\ng, $GITHUB_ORG:maintainer, role:admin"
  }
}'

echo "✓ GitHub組織「$GITHUB_ORG」でArgoCD設定更新完了"
EOF

elif [[ -n "$GITHUB_USER" ]]; then
    print_status "GitHubユーザー「$GITHUB_USER」でArgoCD設定を更新中..."
    
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << EOF
# GitHubユーザー設定でConfigMapを更新（組織制限なし）
kubectl patch configmap argocd-cm -n argocd --type merge -p '{
  "data": {
    "url": "https://argocd.qroksera.com",
    "dex.config": "connectors:\\n- type: github\\n  id: github\\n  name: GitHub\\n  config:\\n    clientId: $GITHUB_CLIENT_ID\\n    clientSecret: \\$dex.github.clientSecret\\n    redirectURI: https://argocd.qroksera.com/api/dex/callback"
  }
}'

# RBAC設定を特定ユーザー用に更新
kubectl patch configmap argocd-rbac-cm -n argocd --type merge -p '{
  "data": {
    "policy.csv": "# GitHubユーザー「$GITHUB_USER」に管理者権限を付与\\ng, $GITHUB_USER, role:admin"
  }
}'

echo "✓ GitHubユーザー「$GITHUB_USER」でArgoCD設定更新完了"
EOF

fi

# ArgoCD サーバー再起動
print_status "ArgoCD サーバーを再起動中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
# ArgoCD サーバーを再起動
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout restart deployment argocd-dex-server -n argocd

# 再起動完了を待機
kubectl rollout status deployment argocd-server -n argocd --timeout=300s
kubectl rollout status deployment argocd-dex-server -n argocd --timeout=300s

echo "✓ ArgoCD サーバー再起動完了"
EOF

print_status "✓ ArgoCD サーバー再起動完了"

# 設定確認
print_status "更新された設定を確認中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
echo "=== 更新されたArgoCD ConfigMap ==="
kubectl get configmap argocd-cm -n argocd -o yaml | grep -A 15 "dex.config"

echo -e "\n=== 更新されたArgoCD RBAC ConfigMap ==="
kubectl get configmap argocd-rbac-cm -n argocd -o yaml | grep -A 10 "policy.csv"
EOF

print_status "=== ArgoCD GitHub設定更新完了 ==="

echo ""
echo "✅ 設定更新完了:"
if [[ -n "$GITHUB_ORG" ]]; then
    echo "- GitHub組織: $GITHUB_ORG"
    echo "- 組織のadmin/maintainerチームメンバーに管理者権限付与"
elif [[ -n "$GITHUB_USER" ]]; then
    echo "- GitHubユーザー: $GITHUB_USER"
    echo "- 指定されたユーザーに管理者権限付与"
fi
echo ""
echo "🌐 アクセス方法:"
echo "1. ArgoCD UI: https://argocd.qroksera.com"
echo "2. 「LOG IN VIA GITHUB」ボタンでGitHub認証"
echo "3. 初回ログイン時にGitHub認可画面が表示される"
echo ""
echo "📝 GitHub OAuth App設定確認:"
echo "- Authorization callback URL: https://argocd.qroksera.com/api/dex/callback"
if [[ -n "$GITHUB_ORG" ]]; then
    echo "- Organization access: 「$GITHUB_ORG」組織への第三者アクセスを有効化"
fi
echo ""
echo "⚠️ 注意事項:"
echo "- 初回ログイン時にGitHub側で認可が必要です"
echo "- 組織の場合、Third-party accessが有効になっている必要があります"