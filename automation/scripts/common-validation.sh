#!/bin/bash
# 検証用共通関数
# 各種チェックと検証処理を統一

# 共通関数を読み込む
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-colors.sh" || true

# ネットワーク接続確認
check_network_connectivity() {
    local target="${1:-8.8.8.8}"
    local timeout="${2:-5}"
    
    if ping -c 1 -W "$timeout" "$target" &> /dev/null; then
        return 0
    else
        print_error "ネットワーク接続できません: $target"
        return 1
    fi
}

# ポート開放確認
check_port_open() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"
    
    if timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# サービス稼働確認
check_service_running() {
    local service="$1"
    
    if systemctl is-active --quiet "$service"; then
        return 0
    else
        print_error "サービスが稼働していません: $service"
        return 1
    fi
}

# コマンド存在確認
check_command_exists() {
    local cmd="$1"
    
    if command -v "$cmd" &> /dev/null; then
        return 0
    else
        print_error "コマンドが見つかりません: $cmd"
        return 1
    fi
}

# ディスク容量確認
check_disk_space() {
    local path="$1"
    local required_gb="${2:-10}"
    
    local available_gb=$(df -BG "$path" | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [[ $available_gb -ge $required_gb ]]; then
        return 0
    else
        print_error "ディスク容量不足: ${available_gb}GB < ${required_gb}GB required"
        return 1
    fi
}

# メモリ容量確認
check_memory() {
    local required_gb="${1:-4}"
    
    local available_gb=$(free -g | awk '/^Mem:/ {print $7}')
    
    if [[ $available_gb -ge $required_gb ]]; then
        return 0
    else
        print_error "メモリ不足: ${available_gb}GB < ${required_gb}GB required"
        return 1
    fi
}

# CPU数確認
check_cpu_cores() {
    local required="${1:-2}"
    
    local cores=$(nproc)
    
    if [[ $cores -ge $required ]]; then
        return 0
    else
        print_error "CPU不足: ${cores} < ${required} cores required"
        return 1
    fi
}

# Kubernetes API確認
check_k8s_api() {
    local host="${1:-192.168.122.10}"
    local port="${2:-6443}"
    
    if check_port_open "$host" "$port"; then
        return 0
    else
        print_error "Kubernetes APIに接続できません: $host:$port"
        return 1
    fi
}

# kubectl設定確認
check_kubectl_config() {
    if [[ -f "$HOME/.kube/config" ]]; then
        if kubectl cluster-info &> /dev/null; then
            return 0
        else
            print_error "kubectl設定が無効です"
            return 1
        fi
    else
        print_error "kubectl設定ファイルが見つかりません"
        return 1
    fi
}

# Docker/Containerd確認
check_container_runtime() {
    if systemctl is-active --quiet docker; then
        print_status "Container runtime: Docker"
        return 0
    elif systemctl is-active --quiet containerd; then
        print_status "Container runtime: containerd"
        return 0
    else
        print_error "コンテナランタイムが稼働していません"
        return 1
    fi
}

# バージョン比較
version_ge() {
    # バージョンが $1 >= $2 かチェック
    printf '%s\n%s' "$2" "$1" | sort -V -C
}

# IPアドレス検証
is_valid_ip() {
    local ip="$1"
    local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    if [[ $ip =~ $regex ]]; then
        IFS='.' read -ra OCTETS <<< "$ip"
        for octet in "${OCTETS[@]}"; do
            if [[ $octet -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# CIDR検証
is_valid_cidr() {
    local cidr="$1"
    local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'
    
    if [[ $cidr =~ $regex ]]; then
        local ip="${cidr%/*}"
        local prefix="${cidr#*/}"
        
        if is_valid_ip "$ip" && [[ $prefix -ge 0 ]] && [[ $prefix -le 32 ]]; then
            return 0
        fi
    fi
    return 1
}

# 必須環境変数チェック
check_required_env() {
    local vars=("$@")
    local missing=()
    
    for var in "${vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            missing+=("$var")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "必須環境変数が設定されていません: ${missing[*]}"
        return 1
    fi
    
    return 0
}

# ファイル検証（チェックサム）
verify_file_checksum() {
    local file="$1"
    local expected_checksum="$2"
    local algorithm="${3:-sha256}"
    
    local actual_checksum
    case $algorithm in
        sha256)
            actual_checksum=$(sha256sum "$file" | awk '{print $1}')
            ;;
        md5)
            actual_checksum=$(md5sum "$file" | awk '{print $1}')
            ;;
        *)
            print_error "不明なアルゴリズム: $algorithm"
            return 1
            ;;
    esac
    
    if [[ "$actual_checksum" == "$expected_checksum" ]]; then
        return 0
    else
        print_error "チェックサム不一致: $file"
        return 1
    fi
}