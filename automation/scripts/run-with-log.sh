#!/bin/bash
# ログ記録付きコマンド実行スクリプト

set -euo pipefail

LOG_FILE="${1:-make-all.log}"
shift

# ログファイルの準備
echo "ℹ️ 実行開始: $(date '+%Y-%m-%d %H:%M:%S')" > "$LOG_FILE"
echo "ℹ️ コマンド: $*" >> "$LOG_FILE"
echo "---" >> "$LOG_FILE"

# コマンドを実行してログに記録
"$@" 2>&1 | tee -a "$LOG_FILE"
EXIT_CODE=${PIPESTATUS[0]}

# 実行結果をログに追記
echo "---" >> "$LOG_FILE"
echo "ℹ️ 実行終了: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
echo "ℹ️ 終了コード: $EXIT_CODE" >> "$LOG_FILE"

# 元のコマンドの終了コードを返す
exit $EXIT_CODE