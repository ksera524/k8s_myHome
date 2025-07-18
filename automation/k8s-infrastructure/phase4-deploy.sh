#!/bin/bash

# Phase 4: 基本インフラ構築スクリプト
# k8s-infrastructure-deploy.shのエイリアス

set -euo pipefail

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
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

print_status "=== Phase 4: 基本インフラ構築 ==="
print_status "k8s-infrastructure-deploy.sh を実行します"

# メインスクリプトの実行
if [[ -f "$SCRIPT_DIR/k8s-infrastructure-deploy.sh" ]]; then
    exec "$SCRIPT_DIR/k8s-infrastructure-deploy.sh" "$@"
else
    print_warning "k8s-infrastructure-deploy.sh が見つかりません"
    exit 1
fi