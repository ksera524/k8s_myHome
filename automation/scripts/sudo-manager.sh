#!/bin/bash
# sudo権限管理の改善版
# より安全で簡潔なsudo権限管理

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-colors.sh" || true

# PIDファイル
SUDO_PID_FILE="/tmp/sudo_manager_${USER}.pid"
SUDO_LOCK_FILE="/tmp/sudo_manager_${USER}.lock"

# sudo権限取得（対話的）
acquire_sudo() {
    print_status "sudo権限を取得中..."
    
    # 既にsudo権限がある場合はスキップ
    if sudo -n true 2>/dev/null; then
        print_success "✓ sudo権限は既に有効です"
        return 0
    fi
    
    # sudo権限を要求
    sudo -v || {
        print_error "sudo権限の取得に失敗しました"
        return 1
    }
    
    print_success "✓ sudo権限を取得しました"
}

# sudo権限維持（バックグラウンド）
maintain_sudo() {
    # ロックファイルで重複起動防止
    if [[ -f "$SUDO_LOCK_FILE" ]]; then
        local existing_pid=$(cat "$SUDO_PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
            print_warning "sudo権限維持プロセスは既に実行中です (PID: $existing_pid)"
            return 0
        fi
    fi
    
    # ロックファイル作成
    touch "$SUDO_LOCK_FILE"
    
    # バックグラウンドプロセス起動
    (
        trap 'rm -f "$SUDO_PID_FILE" "$SUDO_LOCK_FILE"' EXIT
        echo $$ > "$SUDO_PID_FILE"
        
        while true; do
            sudo -n true 2>/dev/null || exit 0
            sleep 50
        done
    ) &
    
    local bg_pid=$!
    echo "$bg_pid" > "$SUDO_PID_FILE"
    
    print_success "✓ sudo権限維持プロセスを開始しました (PID: $bg_pid)"
}

# sudo権限維持停止
stop_maintain() {
    if [[ -f "$SUDO_PID_FILE" ]]; then
        local pid=$(cat "$SUDO_PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]]; then
            if kill "$pid" 2>/dev/null; then
                print_success "✓ sudo権限維持プロセスを停止しました (PID: $pid)"
            fi
        fi
        rm -f "$SUDO_PID_FILE" "$SUDO_LOCK_FILE"
    else
        print_status "sudo権限維持プロセスは実行されていません"
    fi
}

# sudo権限でコマンド実行（エラーハンドリング付き）
sudo_exec() {
    local cmd="$*"
    
    # sudo権限確認
    if ! sudo -n true 2>/dev/null; then
        print_error "sudo権限がありません。先に acquire_sudo を実行してください"
        return 1
    fi
    
    # コマンド実行
    sudo -n bash -c "$cmd"
}

# クリーンアップ（スクリプト終了時用）
cleanup_sudo() {
    stop_maintain
    # sudo権限のタイムスタンプをリセット（オプション）
    # sudo -k
}

# トラップ設定用関数
setup_sudo_trap() {
    trap 'cleanup_sudo' EXIT INT TERM
}

# 使用例表示
show_usage() {
    cat <<EOF
sudo権限管理ユーティリティ

使用方法:
    source $(basename "$0")
    
    # sudo権限取得と維持
    acquire_sudo
    maintain_sudo
    
    # コマンド実行
    sudo_exec "apt-get update"
    
    # 終了時
    cleanup_sudo

関数:
    acquire_sudo    - sudo権限を対話的に取得
    maintain_sudo   - バックグラウンドで権限を維持
    stop_maintain   - 権限維持プロセスを停止
    sudo_exec       - sudo権限でコマンドを実行
    cleanup_sudo    - クリーンアップ
    setup_sudo_trap - 自動クリーンアップ用トラップ設定
EOF
}

# 直接実行された場合
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        start)
            acquire_sudo
            maintain_sudo
            ;;
        stop)
            stop_maintain
            ;;
        status)
            if [[ -f "$SUDO_PID_FILE" ]]; then
                local pid=$(cat "$SUDO_PID_FILE")
                if kill -0 "$pid" 2>/dev/null; then
                    print_status "sudo権限維持プロセスは実行中です (PID: $pid)"
                else
                    print_warning "PIDファイルは存在しますが、プロセスは実行されていません"
                fi
            else
                print_status "sudo権限維持プロセスは実行されていません"
            fi
            ;;
        *)
            show_usage
            ;;
    esac
fi