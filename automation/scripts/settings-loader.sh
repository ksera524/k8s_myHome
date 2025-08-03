#!/bin/bash

# settings.toml読み込みヘルパースクリプト
# make all実行時の標準入力を自動化

set -euo pipefail

# スクリプトディレクトリ取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOMATION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SETTINGS_FILE="$AUTOMATION_DIR/settings.toml"

# カラー設定
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[SETTINGS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[SETTINGS]${NC} $1"
}

print_error() {
    echo -e "${RED}[SETTINGS]${NC} $1"
}

print_debug() {
    echo -e "${BLUE}[SETTINGS]${NC} $1"
}

# TOMLパーサー（簡易版）
# セクション[section]とkey=valueのペアを抽出
parse_toml() {
    local file="$1"
    local section=""
    local key=""
    local value=""
    
    while IFS= read -r line; do
        # コメント行をスキップ
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]]; then
            continue
        fi
        
        # セクション行の処理
        if [[ "$line" =~ ^\[([^\]]+)\] ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi
        
        # キー=値の処理
        if [[ "$line" =~ ^[[:space:]]*([^=]+)[[:space:]]*=[[:space:]]*\"?([^\"]*) ]]; then
            key="${BASH_REMATCH[1]// /}"
            value="${BASH_REMATCH[2]}"
            # 末尾の"を削除
            value="${value%\"}"
            
            if [[ -n "$section" && -n "$key" ]]; then
                # 環境変数として設定（セクション名_キー名=値）
                local env_name="${section^^}_${key^^}"
                export "$env_name=$value"
                if [[ "$value" != "" && ! "$key" =~ (token|password) ]]; then
                    print_debug "設定読み込み: ${env_name}=${value}"
                elif [[ "$value" != "" ]]; then
                    print_debug "設定読み込み: ${env_name}=***masked***"
                fi
            fi
        fi
    done < "$file"
}

# 設定ファイル読み込み
load_settings() {
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        print_warning "設定ファイルが見つかりません: $SETTINGS_FILE"
        print_warning "デフォルト設定で実行されます"
        return 1
    fi
    
    print_status "設定ファイル読み込み中: $SETTINGS_FILE"
    parse_toml "$SETTINGS_FILE"
    print_status "設定ファイル読み込み完了"
    
    # 重要な環境変数の設定
    export_important_variables
    
    return 0
}

# 重要な環境変数の設定
export_important_variables() {
    # PULUMI_ACCESS_TOKEN
    if [[ -n "${PULUMI_ACCESS_TOKEN:-}" ]]; then
        export PULUMI_ACCESS_TOKEN="${PULUMI_ACCESS_TOKEN}"
        print_debug "PULUMI_ACCESS_TOKEN環境変数を設定済み"
    fi
    
    # その他の一般的な環境変数
    if [[ -n "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]]; then
        export GITHUB_TOKEN="${GITHUB_PERSONAL_ACCESS_TOKEN}"
        print_debug "GITHUB_TOKEN環境変数を設定済み"
    fi
    
}

# 自動応答関数群
auto_answer_usb_device() {
    if [[ -n "${HOST_SETUP_USB_DEVICE_NAME:-}" ]]; then
        echo "${HOST_SETUP_USB_DEVICE_NAME}"
        return 0
    fi
    return 1
}

auto_answer_kubernetes_keyring() {
    if [[ -n "${KUBERNETES_OVERWRITE_KUBERNETES_KEYRING:-}" ]]; then
        echo "${KUBERNETES_OVERWRITE_KUBERNETES_KEYRING}"
        return 0
    fi
    return 1
}

auto_answer_pulumi_token() {
    if [[ -n "${PULUMI_ACCESS_TOKEN:-}" ]]; then
        echo "${PULUMI_ACCESS_TOKEN}"
        return 0
    fi
    return 1
}


auto_answer_github_token() {
    if [[ -n "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]]; then
        echo "${GITHUB_PERSONAL_ACCESS_TOKEN}"
        return 0
    fi
    return 1
}

auto_answer_github_repo() {
    if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
        echo "${GITHUB_REPOSITORY}"
        return 0
    fi
    return 1
}

auto_answer_harbor_password() {
    if [[ -n "${HARBOR_ADMIN_PASSWORD:-}" ]]; then
        echo "${HARBOR_ADMIN_PASSWORD}"
        return 0
    fi
    return 1
}

auto_answer_confirm() {
    if [[ "${AUTOMATION_AUTO_CONFIRM_OVERWRITE:-}" == "true" ]]; then
        echo "y"
        return 0
    fi
    return 1
}

# expectスタイルの自動応答
setup_auto_responses() {
    # expectがインストールされているかチェック
    if ! command -v expect >/dev/null 2>&1; then
        print_warning "expectコマンドが見つかりません"
        print_warning "sudo apt-get install expect でインストールできます"
        return 1
    fi
    
    # 一時的なexpectスクリプト作成
    cat > "/tmp/auto_responses.exp" << 'EOF'
#!/usr/bin/expect -f

# タイムアウト設定
set timeout 300

# 引数取得
set command [lindex $argv 0]

# コマンド実行
spawn {*}$command

# 自動応答パターン
expect {
    "Enter the device name*" {
        if {[info exists env(HOST_SETUP_USB_DEVICE_NAME)] && $env(HOST_SETUP_USB_DEVICE_NAME) ne ""} {
            send "$env(HOST_SETUP_USB_DEVICE_NAME)\r"
            exp_continue
        } else {
            interact
        }
    }
    "*上書きしますか*" {
        if {[info exists env(KUBERNETES_OVERWRITE_KUBERNETES_KEYRING)] && $env(KUBERNETES_OVERWRITE_KUBERNETES_KEYRING) ne ""} {
            send "$env(KUBERNETES_OVERWRITE_KUBERNETES_KEYRING)\r"
            exp_continue
        } else {
            interact
        }
    }
    "Pulumi Access Token*" {
        if {[info exists env(PULUMI_ACCESS_TOKEN)] && $env(PULUMI_ACCESS_TOKEN) ne ""} {
            send "$env(PULUMI_ACCESS_TOKEN)\r"
            exp_continue
        } else {
            interact
        }
    }
    "GitHub Personal Access Token*" {
        if {[info exists env(GITHUB_PERSONAL_ACCESS_TOKEN)] && $env(GITHUB_PERSONAL_ACCESS_TOKEN) ne ""} {
            send "$env(GITHUB_PERSONAL_ACCESS_TOKEN)\r"
            exp_continue
        } else {
            interact
        }
    }
    "GitHub Repository*" {
        if {[info exists env(GITHUB_REPOSITORY)] && $env(GITHUB_REPOSITORY) ne ""} {
            send "$env(GITHUB_REPOSITORY)\r"
            exp_continue
        } else {
            interact
        }
    }
    "Harbor管理者パスワード*" {
        if {[info exists env(HARBOR_ADMIN_PASSWORD)] && $env(HARBOR_ADMIN_PASSWORD) ne ""} {
            send "$env(HARBOR_ADMIN_PASSWORD)\r"
            exp_continue
        } else {
            interact
        }
    }
    "*続行しますか*" {
        if {[info exists env(AUTOMATION_AUTO_CONFIRM_OVERWRITE)] && $env(AUTOMATION_AUTO_CONFIRM_OVERWRITE) eq "true"} {
            send "y\r"
            exp_continue
        } else {
            interact
        }
    }
    eof {
        exit
    }
    timeout {
        puts "タイムアウトしました"
        exit 1
    }
}
EOF
    chmod +x "/tmp/auto_responses.exp"
    print_debug "自動応答スクリプトを作成: /tmp/auto_responses.exp"
}

# メイン関数
main() {
    local command="$1"
    
    case "$command" in
        "load")
            load_settings
            ;;
        "setup-expect")
            load_settings
            setup_auto_responses
            ;;
        "run-with-auto-response")
            shift
            load_settings
            setup_auto_responses
            print_status "自動応答でコマンド実行: $*"
            /tmp/auto_responses.exp "$@"
            ;;
        *)
            echo "使用方法: $0 {load|setup-expect|run-with-auto-response <command>}"
            echo ""
            echo "コマンド:"
            echo "  load                      - 設定ファイルを読み込み環境変数に設定"
            echo "  setup-expect              - 設定読み込み + expect自動応答スクリプト作成"  
            echo "  run-with-auto-response    - 自動応答でコマンド実行"
            echo ""
            echo "例:"
            echo "  source $0 load"
            echo "  $0 run-with-auto-response make all"
            exit 1
            ;;
    esac
}

# 引数チェック
if [[ $# -eq 0 ]]; then
    main "load"
else
    main "$@"
fi