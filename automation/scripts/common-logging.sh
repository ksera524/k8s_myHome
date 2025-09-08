#!/bin/bash

# 統一ログ機能
# すべてのスクリプトで共通のログ出力形式を提供

# ========================================
# ログレベル定義
# ========================================
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARNING=2
LOG_LEVEL_ERROR=3
LOG_LEVEL_CRITICAL=4

# デフォルトログレベル（環境変数で上書き可能）
CURRENT_LOG_LEVEL="${LOG_LEVEL:-1}"

# ========================================
# ログ設定
# ========================================
# ログファイルパス（環境変数で上書き可能）
LOG_FILE="${LOG_FILE:-}"
# タイムスタンプ形式
LOG_TIMESTAMP_FORMAT="${LOG_TIMESTAMP_FORMAT:-%Y-%m-%d %H:%M:%S}"
# ログフォーマット（JSON出力オプション）
LOG_FORMAT="${LOG_FORMAT:-text}"

# ========================================
# 絵文字定義（統一）
# ========================================
EMOJI_INFO="ℹ️"
EMOJI_SUCCESS="✅"
EMOJI_WARNING="⚠️"
EMOJI_ERROR="❌"
EMOJI_DEBUG="🔍"
EMOJI_CRITICAL="🚨"
EMOJI_STATUS="📋"

# ========================================
# 内部関数
# ========================================

# タイムスタンプ取得
_get_timestamp() {
    date +"${LOG_TIMESTAMP_FORMAT}"
}

# ログ出力（内部用）
_log_output() {
    local level="$1"
    local emoji="$2"
    local prefix="$3"
    local message="$4"
    local caller="${5:-${BASH_SOURCE[2]:-unknown}}"
    local line="${6:-${BASH_LINENO[1]:-0}}"
    
    # ログレベルチェック
    if [[ "$level" -lt "$CURRENT_LOG_LEVEL" ]]; then
        return 0
    fi
    
    # 出力フォーマット選択
    local output=""
    case "$LOG_FORMAT" in
        json)
            output=$(printf '{"timestamp":"%s","level":"%s","message":"%s","file":"%s","line":%d}' \
                "$(_get_timestamp)" "$prefix" "$message" "$caller" "$line")
            ;;
        *)
            # テキスト形式（デフォルト）
            if [[ -n "$LOG_FILE" ]]; then
                # ファイル出力時はタイムスタンプとメタ情報を含む
                output="[$(_get_timestamp)] [$prefix] $message (${caller##*/}:$line)"
            else
                # コンソール出力時は絵文字と簡潔な形式
                output="$emoji $message"
            fi
            ;;
    esac
    
    # 出力先選択
    if [[ -n "$LOG_FILE" ]]; then
        echo "$output" >> "$LOG_FILE"
    fi
    
    # 標準出力/エラー出力
    if [[ "$level" -ge "$LOG_LEVEL_ERROR" ]]; then
        echo "$output" >&2
    else
        echo "$output"
    fi
}

# ========================================
# パブリック関数
# ========================================

# デバッグログ
log_debug() {
    _log_output "$LOG_LEVEL_DEBUG" "$EMOJI_DEBUG" "DEBUG" "$1" "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}"
}

# 情報ログ
log_info() {
    _log_output "$LOG_LEVEL_INFO" "$EMOJI_INFO" "INFO" "$1" "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}"
}

# ステータスログ（情報レベル）
log_status() {
    _log_output "$LOG_LEVEL_INFO" "$EMOJI_STATUS" "STATUS" "$1" "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}"
}

# 成功ログ（情報レベル）
log_success() {
    _log_output "$LOG_LEVEL_INFO" "$EMOJI_SUCCESS" "SUCCESS" "$1" "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}"
}

# 警告ログ
log_warning() {
    _log_output "$LOG_LEVEL_WARNING" "$EMOJI_WARNING" "WARNING" "$1" "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}"
}

# エラーログ
log_error() {
    _log_output "$LOG_LEVEL_ERROR" "$EMOJI_ERROR" "ERROR" "$1" "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}"
}

# クリティカルログ
log_critical() {
    _log_output "$LOG_LEVEL_CRITICAL" "$EMOJI_CRITICAL" "CRITICAL" "$1" "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}"
}


# ========================================
# ログレベル設定関数
# ========================================

# ログレベル設定
set_log_level() {
    case "${1,,}" in
        debug)   CURRENT_LOG_LEVEL=$LOG_LEVEL_DEBUG ;;
        info)    CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO ;;
        warning|warn) CURRENT_LOG_LEVEL=$LOG_LEVEL_WARNING ;;
        error)   CURRENT_LOG_LEVEL=$LOG_LEVEL_ERROR ;;
        critical|crit) CURRENT_LOG_LEVEL=$LOG_LEVEL_CRITICAL ;;
        *)       log_warning "Unknown log level: $1" ;;
    esac
}

# ログファイル設定
set_log_file() {
    LOG_FILE="$1"
    # ディレクトリが存在しない場合は作成
    local log_dir="$(dirname "$LOG_FILE")"
    [[ -d "$log_dir" ]] || mkdir -p "$log_dir"
}

# ログフォーマット設定
set_log_format() {
    case "${1,,}" in
        json|text) LOG_FORMAT="${1,,}" ;;
        *) log_warning "Unknown log format: $1" ;;
    esac
}

# ========================================
# 初期化
# ========================================

# settings.toml からログ設定を読み込み（存在する場合）
if [[ -n "${LOGGING_LOG_DIR:-}" ]]; then
    set_log_file "${LOGGING_LOG_DIR}/k8s-myhome-$(date +%Y%m%d).log"
fi

if [[ -n "${LOGGING_LOG_LEVEL:-}" ]]; then
    set_log_level "${LOGGING_LOG_LEVEL}"
fi

if [[ "${LOGGING_DEBUG:-false}" == "true" ]]; then
    CURRENT_LOG_LEVEL=$LOG_LEVEL_DEBUG
fi

# ========================================
# 関数エクスポート
# ========================================
export -f log_debug
export -f log_info
export -f log_status
export -f log_success
export -f log_warning
export -f log_error
export -f log_critical
export -f set_log_level
export -f set_log_file
export -f set_log_format

# 環境変数エクスポート
export CURRENT_LOG_LEVEL
export LOG_FILE
export LOG_FORMAT