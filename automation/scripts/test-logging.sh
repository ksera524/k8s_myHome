#!/bin/bash

# ログ機能テストスクリプト

# スクリプトディレクトリ取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 統一ログ機能を読み込み
source "$SCRIPT_DIR/common-logging.sh"

echo "=== ログ機能テスト開始 ==="
echo ""

echo "1. 基本的なログ出力テスト:"
log_debug "これはデバッグメッセージです"
log_info "これは情報メッセージです"
log_status "これはステータスメッセージです"
log_success "これは成功メッセージです"
log_warning "これは警告メッセージです"
log_error "これはエラーメッセージです"
log_critical "これはクリティカルメッセージです"

echo ""
echo "2. ログレベル変更テスト:"

echo "   現在のログレベル: INFO ($CURRENT_LOG_LEVEL)"
log_debug "このデバッグメッセージは表示されません（レベル: INFO）"

echo "   ログレベルをDEBUGに変更..."
set_log_level debug
log_debug "このデバッグメッセージは表示されます（レベル: DEBUG）"

echo ""
echo "3. ログファイル出力テスト:"
TEST_LOG_FILE="/tmp/test-k8s-myhome.log"
set_log_file "$TEST_LOG_FILE"
log_info "このメッセージはファイルとコンソールの両方に出力されます"
echo "   ログファイル内容:"
if [[ -f "$TEST_LOG_FILE" ]]; then
    tail -n 1 "$TEST_LOG_FILE"
    rm -f "$TEST_LOG_FILE"
else
    echo "   エラー: ログファイルが作成されませんでした"
fi

echo ""
echo "4. JSON形式テスト:"
set_log_format json
log_info "JSON形式のメッセージ"
set_log_format text
log_info "テキスト形式に戻しました"

echo ""
echo "5. settings-loader.sh との統合テスト:"
source "$SCRIPT_DIR/settings-loader.sh" test 2>&1 | head -3

echo ""
echo "=== ログ機能テスト完了 ==="