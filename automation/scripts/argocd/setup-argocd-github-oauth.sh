#!/bin/bash

# ArgoCD GitHub OAuth設定スクリプト (GitOps + External Secret統合版)

set -euo pipefail

# スクリプトディレクトリ取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 統一ログ機能を読み込み
source "$SCRIPT_DIR/../common-logging.sh"

log_status "=== ArgoCD GitHub OAuth 最終統合確認 ==="

# SSH known_hosts クリーンアップ
log_debug "SSH known_hosts をクリーンアップ中..."
ssh-keygen -f "$HOME/.ssh/known_hosts" -R '192.168.122.10' 2>/dev/null || true

# k8sクラスタ接続確認
log_debug "k8sクラスタ接続を確認中..."
if ! ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=10 k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
    log_error "k8sクラスタに接続できません"
    exit 1
fi

log_status "ArgoCD GitHub OAuth統合状態を確認中..."

# リモートでスクリプトを実行
scp -q "$SCRIPT_DIR/check-oauth-remote.sh" k8suser@192.168.122.10:/tmp/check-oauth-remote.sh 2>/dev/null
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 'bash /tmp/check-oauth-remote.sh && rm -f /tmp/check-oauth-remote.sh'

log_status "=== ArgoCD GitHub OAuth確認完了 ==="

echo ""
echo "🔧 GitHub OAuth設定状況:"
echo "- Client ID: ESO/設定ファイル経由で管理"
echo "- Client Secret: External Secret自動管理"
echo "- 設定方式: GitOps + External Secret直接統合"
echo ""
echo "🌐 アクセス方法:"
echo "- ArgoCD UI: https://argocd.qroksera.com"
echo "- 「LOG IN VIA GITHUB」でGitHub認証"
echo ""
echo "⚠️  まだLogin failedが発生する場合:"
echo "1. 数分待ってからもう一度試してください"
echo "2. ArgoCD Podの再起動を手動実行してください"
echo "3. External Secretの同期状態を確認してください"