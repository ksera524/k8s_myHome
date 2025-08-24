#!/bin/bash
# レガシー互換性のためのラッパー
# 新しいsudo-manager.shを使用

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/sudo-manager.sh"

# レガシー互換性のため、従来の動作を維持
print_status "sudo keepaliveプロセスをクリーンアップ中（新しいsudo-managerを使用）"
cleanup_sudo