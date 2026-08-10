#!/bin/bash

# settings.toml読み込みヘルパースクリプト

set -euo pipefail

# スクリプトディレクトリ取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOMATION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SETTINGS_FILE="$AUTOMATION_DIR/settings.toml"

# 統一ログ機能を読み込み
source "$SCRIPT_DIR/common-logging.sh"

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
                    log_debug "設定読み込み: PULUMI_ACCESS_TOKEN=***masked***"
                elif [[ "$value" != "" && ! "$key" =~ (token|password) ]]; then
                    log_debug "設定読み込み: ${env_name}=${value}"
                elif [[ "$value" != "" ]]; then
                    log_debug "設定読み込み: ${env_name}=***masked***"
                fi
            fi
        fi
    done < "$file"
}

# 設定ファイル読み込み
load_settings() {
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        log_warning "設定ファイルが見つかりません: $SETTINGS_FILE"
        log_warning "デフォルト設定で実行されます"
        return 1
    fi
    
    # NON_INTERACTIVEまたはQUIET_LOGSモードでは詳細ログを抑制
    if [[ "${NON_INTERACTIVE:-false}" != "true" ]] && [[ "${QUIET_LOGS:-false}" != "true" ]]; then
        log_status "設定ファイル読み込み中: $SETTINGS_FILE"
    fi
    parse_toml "$SETTINGS_FILE"
    if [[ "${NON_INTERACTIVE:-false}" != "true" ]] && [[ "${QUIET_LOGS:-false}" != "true" ]]; then
        log_status "設定ファイル読み込み完了"
    fi
    
    # 重要な環境変数の設定
    export_important_variables
    
    return 0
}

# 重要な環境変数の設定
export_important_variables() {
    # Kubernetes設定
    if [[ -n "${KUBERNETES_USER:-}" ]]; then
        export K8S_USER="${KUBERNETES_USER}"
        log_debug "K8S_USER環境変数を設定済み: ${KUBERNETES_USER}"
    fi
    
    if [[ -n "${KUBERNETES_SSH_KEY_PATH:-}" ]]; then
        export K8S_SSH_KEY="${KUBERNETES_SSH_KEY_PATH}"
        log_debug "K8S_SSH_KEY環境変数を設定済み: ${KUBERNETES_SSH_KEY_PATH}"
    fi
    
    # ネットワーク設定の環境変数
    if [[ -n "${NETWORK_CONTROL_PLANE_IP:-}" ]]; then
        export K8S_CONTROL_PLANE_IP="${NETWORK_CONTROL_PLANE_IP}"
        export CONTROL_PLANE_IP="${NETWORK_CONTROL_PLANE_IP}"
        log_debug "K8S_CONTROL_PLANE_IP環境変数を設定済み: ${NETWORK_CONTROL_PLANE_IP}"
    fi
    
    # Pulumi設定
    if [[ -n "${PULUMI_ACCESS_TOKEN:-}" ]]; then
        export PULUMI_ACCESS_TOKEN="${PULUMI_ACCESS_TOKEN}"
        log_debug "PULUMI_ACCESS_TOKEN環境変数を設定済み"
    fi
    
    if [[ -n "${PULUMI_ORGANIZATION:-}" ]]; then
        export PULUMI_ORGANIZATION="${PULUMI_ORGANIZATION}"
        log_debug "PULUMI_ORGANIZATION環境変数を設定済み: ${PULUMI_ORGANIZATION}"
    fi
    
    if [[ -n "${PULUMI_PROJECT:-}" ]]; then
        export PULUMI_PROJECT="${PULUMI_PROJECT}"
        log_debug "PULUMI_PROJECT環境変数を設定済み: ${PULUMI_PROJECT}"
    fi
    
    if [[ -n "${PULUMI_ENVIRONMENT:-}" ]]; then
        export PULUMI_ENVIRONMENT="${PULUMI_ENVIRONMENT}"
        log_debug "PULUMI_ENVIRONMENT環境変数を設定済み: ${PULUMI_ENVIRONMENT}"
    fi
    
    # GitHub設定
    if [[ -n "${GITHUB_USERNAME:-}" ]]; then
        export GITHUB_USERNAME="${GITHUB_USERNAME}"
        log_debug "GITHUB_USERNAME環境変数を設定済み: ${GITHUB_USERNAME}"
    fi
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
        *)
            echo "使用方法: $0 {load}"
            echo ""
            echo "コマンド:"
            echo "  load                      - 設定ファイルを読み込み環境変数に設定"
            echo ""
            echo "例:"
            echo "  source $0 load"
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
