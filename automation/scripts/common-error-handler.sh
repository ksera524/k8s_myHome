#!/bin/bash
# エラーハンドリング用共通関数
# 統一されたエラー処理とロギング

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-logging.sh" || true

# エラーログファイル
ERROR_LOG_DIR="${ERROR_LOG_DIR:-/tmp/k8s-myhome-logs}"
ERROR_LOG_FILE="${ERROR_LOG_DIR}/error-$(date +%Y%m%d-%H%M%S).log"

# エラーハンドラー初期化
init_error_handler() {
    # ログディレクトリ作成
    mkdir -p "$ERROR_LOG_DIR"
    
    # エラートラップ設定
    set -euo pipefail
    trap 'handle_error $? $LINENO "$BASH_COMMAND"' ERR
}

# エラーハンドリング関数
handle_error() {
    local exit_code=$1
    local line_number=$2
    local command="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # エラー情報をログに記録
    {
        echo "[$timestamp] ERROR in ${BASH_SOURCE[1]:-unknown}:${line_number}"
        echo "Command: $command"
        echo "Exit code: $exit_code"
        echo "Stack trace:"
        local i=0
        while caller $i; do
            ((i++))
        done
        echo "---"
    } >> "$ERROR_LOG_FILE"
    
    # コンソールにエラー表示
    log_error "エラーが発生しました (終了コード: $exit_code)"
    log_error "場所: ${BASH_SOURCE[1]:-unknown}:${line_number}"
    log_error "コマンド: $command"
    log_error "詳細はログを確認してください: $ERROR_LOG_FILE"
    
    # クリーンアップ関数が定義されていれば実行
    if declare -f cleanup_on_error >/dev/null; then
        cleanup_on_error
    fi
    
    exit $exit_code
}

# リトライ機能付きコマンド実行
retry_command() {
    local max_attempts="${1:-3}"
    local delay="${2:-5}"
    shift 2
    local command=("$@")
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if "${command[@]}"; then
            return 0
        else
            local exit_code=$?
            log_warning "コマンド失敗 (試行 $attempt/$max_attempts): ${command[*]}"
            
            if [[ $attempt -lt $max_attempts ]]; then
                log_status "${delay}秒後に再試行します..."
                sleep "$delay"
            fi
            
            ((attempt++))
        fi
    done
    
    log_error "最大試行回数に達しました: ${command[*]}"
    return $exit_code
}

# タイムアウト付きコマンド実行
timeout_command() {
    local timeout="${1:-60}"
    shift
    local command=("$@")
    
    if command -v timeout >/dev/null; then
        timeout "$timeout" "${command[@]}"
    else
        # timeoutコマンドがない場合の代替実装
        "${command[@]}" &
        local pid=$!
        local count=0
        
        while kill -0 $pid 2>/dev/null && [[ $count -lt $timeout ]]; do
            sleep 1
            ((count++))
        done
        
        if kill -0 $pid 2>/dev/null; then
            kill -TERM $pid
            sleep 2
            kill -KILL $pid 2>/dev/null || true
            log_error "コマンドがタイムアウトしました: ${command[*]}"
            return 124
        fi
        
        wait $pid
    fi
}

# 条件付き実行
run_if() {
    local condition="$1"
    shift
    
    if eval "$condition"; then
        "$@"
    else
        log_debug "条件を満たさないためスキップ: $condition"
    fi
}

# 安全なファイル操作
safe_backup() {
    local file="$1"
    local backup_dir="${2:-$ERROR_LOG_DIR/backups}"
    
    if [[ -f "$file" ]]; then
        mkdir -p "$backup_dir"
        local backup_file="$backup_dir/$(basename "$file").$(date +%Y%m%d-%H%M%S).bak"
        cp -p "$file" "$backup_file"
        log_status "バックアップ作成: $backup_file"
    fi
}

# ロールバック機能
create_checkpoint() {
    local checkpoint_name="$1"
    local checkpoint_file="$ERROR_LOG_DIR/checkpoint-${checkpoint_name}.txt"
    
    {
        echo "Checkpoint: $checkpoint_name"
        echo "Date: $(date)"
        echo "Script: ${BASH_SOURCE[1]:-unknown}"
        echo "---"
        # 追加の状態情報を保存できる
    } > "$checkpoint_file"
    
    log_status "チェックポイント作成: $checkpoint_name"
}

# プログレス表示
show_progress() {
    local current=$1
    local total=$2
    local task="${3:-Processing}"
    
    local percent=$((current * 100 / total))
    local bar_length=50
    local filled_length=$((percent * bar_length / 100))
    
    printf "\r%s: [" "$task"
    printf "%${filled_length}s" | tr ' ' '='
    printf "%$((bar_length - filled_length))s" | tr ' ' '-'
    printf "] %d%% (%d/%d)" "$percent" "$current" "$total"
    
    if [[ $current -eq $total ]]; then
        echo
    fi
}

# ログローテーション
rotate_logs() {
    local max_logs="${1:-10}"
    local log_pattern="${2:-error-*.log}"
    
    cd "$ERROR_LOG_DIR" || return
    
    local logs=($(ls -t $log_pattern 2>/dev/null))
    local count=${#logs[@]}
    
    if [[ $count -gt $max_logs ]]; then
        for ((i=$max_logs; i<$count; i++)); do
            rm -f "${logs[$i]}"
            log_debug "古いログを削除: ${logs[$i]}"
        done
    fi
}

# デバッグモード設定
set_debug_mode() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        set -x
        export PS4='+ ${BASH_SOURCE##*/}:${LINENO}: '
    fi
}

# エラーサマリー表示
show_error_summary() {
    if [[ -f "$ERROR_LOG_FILE" ]] && [[ -s "$ERROR_LOG_FILE" ]]; then
        log_warning "=== エラーサマリー ==="
        tail -n 20 "$ERROR_LOG_FILE"
        log_warning "===================="
    fi
}