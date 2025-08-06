#!/bin/bash

# Phase 4: 基本インフラ構築スクリプト
# k8s-infrastructure-deploy.shのエイリアス

set -euo pipefail

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 共通色設定スクリプトを読み込み
source "$SCRIPT_DIR/../scripts/common-colors.sh"

print_status "=== Phase 4: 基本インフラ構築 ==="
print_status "k8s-infrastructure-deploy.sh を実行します"

# メインスクリプトの実行
if [[ -f "$SCRIPT_DIR/k8s-infrastructure-deploy.sh" ]]; then
    exec "$SCRIPT_DIR/k8s-infrastructure-deploy.sh" "$@"
else
    print_warning "k8s-infrastructure-deploy.sh が見つかりません"
    exit 1
fi