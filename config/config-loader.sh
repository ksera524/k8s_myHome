#!/bin/bash
# 統一設定ローダー
# YAMLファイルから設定を読み込み、環境変数として設定

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_BASE_DIR="${SCRIPT_DIR}/base"
CONFIG_SECRETS_DIR="${SCRIPT_DIR}/secrets"

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# YAMLパーサー関数（簡易版）
parse_yaml() {
    local prefix=$2
    local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
    sed -ne "s|^\($s\):|\1|" \
         -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
         -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
    awk -F$fs '{
        indent = length($1)/2;
        vname[indent] = $2;
        for (i in vname) {if (i > indent) {delete vname[i]}}
        if (length($3) > 0) {
            vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
            printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
        }
    }'
}

# .envファイルから環境変数を読み込む
load_env() {
    local env_file="${CONFIG_SECRETS_DIR}/.env"
    if [[ -f "$env_file" ]]; then
        echo -e "${GREEN}Loading environment variables from .env...${NC}"
        set -a
        source "$env_file"
        set +a
    else
        echo -e "${YELLOW}Warning: .env file not found at ${env_file}${NC}"
        echo -e "${YELLOW}Copy .env.example to .env and set your values${NC}"
    fi
}

# 設定ファイルを読み込む
load_config() {
    local config_type=$1
    local config_file="${CONFIG_BASE_DIR}/${config_type}.yaml"
    
    if [[ -f "$config_file" ]]; then
        echo -e "${GREEN}Loading ${config_type} configuration...${NC}"
        eval $(parse_yaml "$config_file" "CONFIG_")
    else
        echo -e "${RED}Error: Configuration file not found: ${config_file}${NC}"
        return 1
    fi
}

# 特定の設定値を取得
get_config_value() {
    local key=$1
    local var_name="CONFIG_${key}"
    echo "${!var_name:-}"
}

# 全設定をエクスポート
export_all_configs() {
    # 環境変数を読み込む
    load_env
    
    # 各設定ファイルを読み込む
    for config in cluster network services infrastructure; do
        load_config "$config"
    done
    
    # レガシー互換性のための変換
    export CONTROL_PLANE_IP="${CONFIG_nodes_control_plane_0_ip:-192.168.122.10}"
    export WORKER_1_IP="${CONFIG_nodes_workers_0_ip:-192.168.122.11}"
    export WORKER_2_IP="${CONFIG_nodes_workers_1_ip:-192.168.122.12}"
    export HARBOR_LB_IP="${CONFIG_service_ips_harbor:-192.168.122.100}"
    export INGRESS_LB_IP="${CONFIG_service_ips_ingress_nginx:-192.168.122.101}"
    export METALLB_IP_START="${CONFIG_metallb_ip_pool_start:-192.168.122.100}"
    export METALLB_IP_END="${CONFIG_metallb_ip_pool_end:-192.168.122.150}"
}

# メイン処理
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    export_all_configs
    echo -e "${GREEN}Configuration loaded successfully${NC}"
fi