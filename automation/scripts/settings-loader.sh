#!/bin/bash

# settings.toml読み込みヘルパースクリプト
# make all実行時の標準入力を自動化

set -euo pipefail

# スクリプトディレクトリ取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOMATION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SETTINGS_FILE="$AUTOMATION_DIR/settings.toml"

# 共通色設定スクリプトを読み込み
source "$SCRIPT_DIR/common-colors.sh"

# 設定固有の印刷関数を定義（[SETTINGS]プレフィックス）
print_settings_status() {
    echo "📋 [SETTINGS] $1"
}

print_settings_warning() {
    echo "⚠️  [SETTINGS] $1"
}

print_settings_error() {
    echo "❌ [SETTINGS] $1"
}

print_settings_debug() {
    echo "🔍 [SETTINGS] $1"
}

# 後方互換性のためのエイリアス
print_status() { print_settings_status "$1"; }
print_warning() { print_settings_warning "$1"; }
print_error() { print_settings_error "$1"; }
print_debug() { print_settings_debug "$1"; }

# TOMLパーサー（拡張版）
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
        
        # キー=値の処理（配列対応）
        if [[ "$line" =~ ^[[:space:]]*([^=]+)[[:space:]]*=[[:space:]]*(.*) ]]; then
            key="${BASH_REMATCH[1]// /}"
            value="${BASH_REMATCH[2]}"
            
            # 配列の開始を検出
            if [[ "$value" == "[" ]]; then
                # 配列の処理をスキップ（後で必要に応じて実装）
                continue
            elif [[ "$value" =~ ^\[ ]]; then
                # 単一行の配列もスキップ
                continue
            else
                # 通常の値のクリーンアップ
                # クォート内の値を抽出（コメントは除外）
                if [[ "$value" =~ ^\"([^\"]*)\" ]]; then
                    # ダブルクォートで囲まれた値
                    value="${BASH_REMATCH[1]}"
                elif [[ "$value" =~ ^\'([^\']*)\' ]]; then
                    # シングルクォートで囲まれた値
                    value="${BASH_REMATCH[1]}"
                else
                    # クォートなしの場合、コメントを削除
                    value="${value%%#*}"
                    # 前後の空白を削除
                    value="${value%% }"
                    value="${value## }"
                fi
            fi
            
            if [[ -n "$section" && -n "$key" ]]; then
                # 環境変数として設定（セクション名_キー名=値）
                local env_name="${section^^}_${key^^}"
                export "$env_name=$value"
                
                # 特別な変数マッピング: PULUMI_ACCESS_TOKEN
                if [[ "$section" == "pulumi" && "$key" == "access_token" ]]; then
                    export PULUMI_ACCESS_TOKEN="$value"
                    print_debug "設定読み込み: PULUMI_ACCESS_TOKEN=***masked***"
                elif [[ "$value" != "" && ! "$key" =~ (token|password) ]]; then
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
    # Kubernetes設定
    if [[ -n "${KUBERNETES_CLUSTER_NAME:-}" ]]; then
        export K8S_CLUSTER_NAME="${KUBERNETES_CLUSTER_NAME}"
        print_debug "K8S_CLUSTER_NAME環境変数を設定済み: ${KUBERNETES_CLUSTER_NAME}"
    fi
    
    if [[ -n "${KUBERNETES_VERSION:-}" ]]; then
        export K8S_VERSION="${KUBERNETES_VERSION}"
        print_debug "K8S_VERSION環境変数を設定済み: ${KUBERNETES_VERSION}"
    fi
    
    if [[ -n "${KUBERNETES_USER:-}" ]]; then
        export K8S_USER="${KUBERNETES_USER}"
        print_debug "K8S_USER環境変数を設定済み: ${KUBERNETES_USER}"
    fi
    
    if [[ -n "${KUBERNETES_SSH_KEY_PATH:-}" ]]; then
        export K8S_SSH_KEY="${KUBERNETES_SSH_KEY_PATH}"
        print_debug "K8S_SSH_KEY環境変数を設定済み: ${KUBERNETES_SSH_KEY_PATH}"
    fi
    
    # ネットワーク設定の環境変数
    if [[ -n "${NETWORK_CONTROL_PLANE_IP:-}" ]]; then
        export K8S_CONTROL_PLANE_IP="${NETWORK_CONTROL_PLANE_IP}"
        export CONTROL_PLANE_IP="${NETWORK_CONTROL_PLANE_IP}"
        print_debug "K8S_CONTROL_PLANE_IP環境変数を設定済み: ${NETWORK_CONTROL_PLANE_IP}"
    fi
    
    if [[ -n "${NETWORK_WORKER_1_IP:-}" ]]; then
        export K8S_WORKER_1_IP="${NETWORK_WORKER_1_IP}"
        export WORKER_1_IP="${NETWORK_WORKER_1_IP}"
        print_debug "K8S_WORKER_1_IP環境変数を設定済み: ${NETWORK_WORKER_1_IP}"
    fi
    
    if [[ -n "${NETWORK_WORKER_2_IP:-}" ]]; then
        export K8S_WORKER_2_IP="${NETWORK_WORKER_2_IP}"
        export WORKER_2_IP="${NETWORK_WORKER_2_IP}"
        print_debug "K8S_WORKER_2_IP環境変数を設定済み: ${NETWORK_WORKER_2_IP}"
    fi
    
    if [[ -n "${NETWORK_GATEWAY_IP:-}" ]]; then
        export GATEWAY_IP="${NETWORK_GATEWAY_IP}"
        print_debug "GATEWAY_IP環境変数を設定済み: ${NETWORK_GATEWAY_IP}"
    fi
    
    if [[ -n "${NETWORK_POD_NETWORK_CIDR:-}" ]]; then
        export POD_NETWORK_CIDR="${NETWORK_POD_NETWORK_CIDR}"
        print_debug "POD_NETWORK_CIDR環境変数を設定済み: ${NETWORK_POD_NETWORK_CIDR}"
    fi
    
    if [[ -n "${NETWORK_SERVICE_CIDR:-}" ]]; then
        export SERVICE_CIDR="${NETWORK_SERVICE_CIDR}"
        print_debug "SERVICE_CIDR環境変数を設定済み: ${NETWORK_SERVICE_CIDR}"
    fi
    
    # MetalLB設定
    if [[ -n "${NETWORK_METALLB_IP_START:-}" ]]; then
        export METALLB_IP_START="${NETWORK_METALLB_IP_START}"
        print_debug "METALLB_IP_START環境変数を設定済み: ${NETWORK_METALLB_IP_START}"
    fi
    
    if [[ -n "${NETWORK_METALLB_IP_END:-}" ]]; then
        export METALLB_IP_END="${NETWORK_METALLB_IP_END}"
        print_debug "METALLB_IP_END環境変数を設定済み: ${NETWORK_METALLB_IP_END}"
    fi
    
    # サービス固定IP（network.harbor_ipの場合）
    if [[ -n "${NETWORK_HARBOR_IP:-}" ]]; then
        export HARBOR_IP="${NETWORK_HARBOR_IP}"
        export HARBOR_LB_IP="${NETWORK_HARBOR_IP}"
        print_debug "HARBOR_IP環境変数を設定済み: ${NETWORK_HARBOR_IP}"
    fi
    
    # サービス固定IP（network.harbor_lb_ipの場合 - 互換性のため）
    if [[ -n "${NETWORK_HARBOR_LB_IP:-}" ]]; then
        export HARBOR_IP="${NETWORK_HARBOR_LB_IP}"
        export HARBOR_LB_IP="${NETWORK_HARBOR_LB_IP}"
        print_debug "HARBOR_IP環境変数を設定済み: ${NETWORK_HARBOR_LB_IP}"
    fi
    
    if [[ -n "${NETWORK_INGRESS_IP:-}" ]]; then
        export INGRESS_IP="${NETWORK_INGRESS_IP}"
        export INGRESS_LB_IP="${NETWORK_INGRESS_IP}"
        print_debug "INGRESS_IP環境変数を設定済み: ${NETWORK_INGRESS_IP}"
    fi
    
    if [[ -n "${NETWORK_ARGOCD_IP:-}" ]]; then
        export ARGOCD_IP="${NETWORK_ARGOCD_IP}"
        export ARGOCD_LB_IP="${NETWORK_ARGOCD_IP}"
        print_debug "ARGOCD_IP環境変数を設定済み: ${NETWORK_ARGOCD_IP}"
    fi
    
    # ポート設定
    if [[ -n "${NETWORK_KUBERNETES_API_PORT:-}" ]]; then
        export K8S_API_PORT="${NETWORK_KUBERNETES_API_PORT}"
        print_debug "K8S_API_PORT環境変数を設定済み: ${NETWORK_KUBERNETES_API_PORT}"
    fi
    
    if [[ -n "${NETWORK_ARGOCD_PORT_FORWARD:-}" ]]; then
        export ARGOCD_PORT_FORWARD="${NETWORK_ARGOCD_PORT_FORWARD}"
        print_debug "ARGOCD_PORT_FORWARD環境変数を設定済み: ${NETWORK_ARGOCD_PORT_FORWARD}"
    fi
    
    if [[ -n "${NETWORK_HARBOR_PORT_FORWARD:-}" ]]; then
        export HARBOR_PORT_FORWARD="${NETWORK_HARBOR_PORT_FORWARD}"
        print_debug "HARBOR_PORT_FORWARD環境変数を設定済み: ${NETWORK_HARBOR_PORT_FORWARD}"
    fi
    
    # Harbor設定
    if [[ -n "${HARBOR_URL:-}" ]]; then
        export HARBOR_URL="${HARBOR_URL}"
        print_debug "HARBOR_URL環境変数を設定済み: ${HARBOR_URL}"
    fi
    
    if [[ -n "${HARBOR_HTTP_PORT:-}" ]]; then
        export HARBOR_HTTP_PORT="${HARBOR_HTTP_PORT}"
        print_debug "HARBOR_HTTP_PORT環境変数を設定済み: ${HARBOR_HTTP_PORT}"
    fi
    
    if [[ -n "${HARBOR_PROJECT:-}" ]]; then
        export HARBOR_PROJECT="${HARBOR_PROJECT}"
        print_debug "HARBOR_PROJECT環境変数を設定済み: ${HARBOR_PROJECT}"
    fi
    
    if [[ -n "${HARBOR_ADMIN_USERNAME:-}" ]]; then
        export HARBOR_ADMIN_USERNAME="${HARBOR_ADMIN_USERNAME}"
        print_debug "HARBOR_ADMIN_USERNAME環境変数を設定済み: ${HARBOR_ADMIN_USERNAME}"
    fi
    
    if [[ -n "${HARBOR_ADMIN_PASSWORD:-}" ]]; then
        export HARBOR_ADMIN_PASSWORD="${HARBOR_ADMIN_PASSWORD}"
        print_debug "HARBOR_ADMIN_PASSWORD環境変数を設定済み: ***masked***"
    fi
    
    # ストレージ設定
    if [[ -n "${STORAGE_BASE_DIR:-}" ]]; then
        export STORAGE_BASE_DIR="${STORAGE_BASE_DIR}"
        print_debug "STORAGE_BASE_DIR環境変数を設定済み: ${STORAGE_BASE_DIR}"
    fi
    
    if [[ -n "${STORAGE_NFS_SHARE:-}" ]]; then
        export NFS_SHARE_DIR="${STORAGE_NFS_SHARE}"
        print_debug "NFS_SHARE_DIR環境変数を設定済み: ${STORAGE_NFS_SHARE}"
    fi
    
    if [[ -n "${STORAGE_LOCAL_VOLUMES:-}" ]]; then
        export LOCAL_VOLUMES_DIR="${STORAGE_LOCAL_VOLUMES}"
        print_debug "LOCAL_VOLUMES_DIR環境変数を設定済み: ${STORAGE_LOCAL_VOLUMES}"
    fi
    
    # バージョン設定
    if [[ -n "${VERSIONS_METALLB:-}" ]]; then
        export METALLB_VERSION="${VERSIONS_METALLB}"
        print_debug "METALLB_VERSION環境変数を設定済み: ${VERSIONS_METALLB}"
    fi
    
    if [[ -n "${VERSIONS_INGRESS_NGINX:-}" ]]; then
        export INGRESS_NGINX_VERSION="${VERSIONS_INGRESS_NGINX}"
        print_debug "INGRESS_NGINX_VERSION環境変数を設定済み: ${VERSIONS_INGRESS_NGINX}"
    fi
    
    if [[ -n "${VERSIONS_CERT_MANAGER:-}" ]]; then
        export CERT_MANAGER_VERSION="${VERSIONS_CERT_MANAGER}"
        print_debug "CERT_MANAGER_VERSION環境変数を設定済み: ${VERSIONS_CERT_MANAGER}"
    fi
    
    if [[ -n "${VERSIONS_ARGOCD:-}" ]]; then
        export ARGOCD_VERSION="${VERSIONS_ARGOCD}"
        print_debug "ARGOCD_VERSION環境変数を設定済み: ${VERSIONS_ARGOCD}"
    fi
    
    if [[ -n "${VERSIONS_HARBOR:-}" ]]; then
        export HARBOR_VERSION="${VERSIONS_HARBOR}"
        print_debug "HARBOR_VERSION環境変数を設定済み: ${VERSIONS_HARBOR}"
    fi
    
    if [[ -n "${VERSIONS_EXTERNAL_SECRETS:-}" ]]; then
        export EXTERNAL_SECRETS_VERSION="${VERSIONS_EXTERNAL_SECRETS}"
        print_debug "EXTERNAL_SECRETS_VERSION環境変数を設定済み: ${VERSIONS_EXTERNAL_SECRETS}"
    fi
    
    # Pulumi設定
    if [[ -n "${PULUMI_ACCESS_TOKEN:-}" ]]; then
        export PULUMI_ACCESS_TOKEN="${PULUMI_ACCESS_TOKEN}"
        print_debug "PULUMI_ACCESS_TOKEN環境変数を設定済み"
    fi
    
    if [[ -n "${PULUMI_ORGANIZATION:-}" ]]; then
        export PULUMI_ORGANIZATION="${PULUMI_ORGANIZATION}"
        print_debug "PULUMI_ORGANIZATION環境変数を設定済み: ${PULUMI_ORGANIZATION}"
    fi
    
    if [[ -n "${PULUMI_PROJECT:-}" ]]; then
        export PULUMI_PROJECT="${PULUMI_PROJECT}"
        print_debug "PULUMI_PROJECT環境変数を設定済み: ${PULUMI_PROJECT}"
    fi
    
    if [[ -n "${PULUMI_ENVIRONMENT:-}" ]]; then
        export PULUMI_ENVIRONMENT="${PULUMI_ENVIRONMENT}"
        print_debug "PULUMI_ENVIRONMENT環境変数を設定済み: ${PULUMI_ENVIRONMENT}"
    fi
    
    # GitHub設定
    if [[ -n "${GITHUB_USERNAME:-}" ]]; then
        export GITHUB_USERNAME="${GITHUB_USERNAME}"
        print_debug "GITHUB_USERNAME環境変数を設定済み: ${GITHUB_USERNAME}"
    fi
    
    if [[ -n "${GITHUB_ARC_REPOSITORIES:-}" ]]; then
        export GITHUB_ARC_REPOSITORIES="${GITHUB_ARC_REPOSITORIES}"
        print_debug "GITHUB_ARC_REPOSITORIES環境変数を設定済み"
    fi
    
    # タイムアウト設定
    if [[ -n "${TIMEOUT_DEFAULT:-}" ]]; then
        export DEFAULT_TIMEOUT="${TIMEOUT_DEFAULT}"
        print_debug "DEFAULT_TIMEOUT環境変数を設定済み: ${TIMEOUT_DEFAULT}"
    fi
    
    if [[ -n "${TIMEOUT_KUBECTL:-}" ]]; then
        export KUBECTL_TIMEOUT="${TIMEOUT_KUBECTL}"
        print_debug "KUBECTL_TIMEOUT環境変数を設定済み: ${TIMEOUT_KUBECTL}"
    fi
    
    if [[ -n "${TIMEOUT_HELM:-}" ]]; then
        export HELM_TIMEOUT="${TIMEOUT_HELM}"
        print_debug "HELM_TIMEOUT環境変数を設定済み: ${TIMEOUT_HELM}"
    fi
    
    if [[ -n "${TIMEOUT_ARGOCD_SYNC:-}" ]]; then
        export ARGOCD_SYNC_TIMEOUT="${TIMEOUT_ARGOCD_SYNC}"
        print_debug "ARGOCD_SYNC_TIMEOUT環境変数を設定済み: ${TIMEOUT_ARGOCD_SYNC}"
    fi
    
    if [[ -n "${TIMEOUT_TERRAFORM:-}" ]]; then
        export TERRAFORM_TIMEOUT="${TIMEOUT_TERRAFORM}"
        print_debug "TERRAFORM_TIMEOUT環境変数を設定済み: ${TIMEOUT_TERRAFORM}"
    fi
    
    # リトライ設定
    if [[ -n "${RETRY_COUNT:-}" ]]; then
        export RETRY_COUNT="${RETRY_COUNT}"
        print_debug "RETRY_COUNT環境変数を設定済み: ${RETRY_COUNT}"
    fi
    
    if [[ -n "${RETRY_DELAY:-}" ]]; then
        export RETRY_DELAY="${RETRY_DELAY}"
        print_debug "RETRY_DELAY環境変数を設定済み: ${RETRY_DELAY}"
    fi
    
    if [[ -n "${RETRY_MAX_DELAY:-}" ]]; then
        export RETRY_MAX_DELAY="${RETRY_MAX_DELAY}"
        print_debug "RETRY_MAX_DELAY環境変数を設定済み: ${RETRY_MAX_DELAY}"
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
    # 常にyを返す（settings.tomlから読み込まれない固定値）
    echo "y"
    return 0
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

# 設定値取得関数
get_config() {
    local section="$1"
    local key="$2"
    local default="${3:-}"
    
    local env_name="${section^^}_${key^^}"
    echo "${!env_name:-$default}"
}

# 設定値の存在確認
has_config() {
    local section="$1"
    local key="$2"
    
    local env_name="${section^^}_${key^^}"
    [[ -n "${!env_name:-}" ]]
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