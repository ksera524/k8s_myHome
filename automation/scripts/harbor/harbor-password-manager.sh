#!/bin/bash

# Harbor パスワード管理スクリプト
# フォールバック用のシンプルな実装

set -euo pipefail

# スクリプトディレクトリ取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 共通色設定スクリプトを読み込み
source "$SCRIPT_DIR/../common-colors.sh"

print_status "=== Harbor パスワード管理（フォールバック） ==="

# デフォルトパスワードを使用
HARBOR_PASSWORD="Harbor12345"
HARBOR_USERNAME="admin"

print_warning "External Secrets が利用できないため、デフォルトパスワードを使用します"
print_status "Harbor認証情報:"
echo "  Username: $HARBOR_USERNAME"
echo "  Password: $HARBOR_PASSWORD"

# 環境変数としてエクスポート
export HARBOR_USERNAME HARBOR_PASSWORD

print_status "✅ Harbor パスワード管理完了（フォールバックモード）"

# セキュリティ注意事項
cat << 'EOF'

⚠️  セキュリティ注意事項:
- デフォルトパスワードが使用されています
- 本番環境では必ずパスワードを変更してください
- External Secrets の使用を強く推奨します

🔧 推奨対応:
1. External Secrets セットアップ:
   cd automation/platform/external-secrets
   ./setup-external-secrets.sh

2. Pulumi ESC パスワード設定:
   ./setup-pulumi-pat.sh --interactive

3. 再デプロイ:
   export PULUMI_ACCESS_TOKEN="pul-xxx..."
   make all

EOF