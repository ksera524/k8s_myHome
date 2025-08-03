#!/bin/bash

# Harbor パスワード管理スクリプト
# フォールバック用のシンプルな実装

set -euo pipefail

# カラー設定
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

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