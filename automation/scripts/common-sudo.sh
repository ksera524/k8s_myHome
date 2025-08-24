#!/bin/bash
# sudo操作用共通関数
# sudo権限管理を簡素化

# sudo -n のラッパー
sudo_n() {
    sudo -n "$@"
}

# ディレクトリ作成と権限設定
create_directory() {
    local dir="$1"
    local owner="${2:-$(whoami)}"
    local perms="${3:-755}"
    
    sudo_n mkdir -p "$dir" || return 1
    sudo_n chown -R "$owner" "$dir" || return 1
    sudo_n chmod "$perms" "$dir" || return 1
}

# ファイルの安全な書き込み（sudo権限）
sudo_write_file() {
    local content="$1"
    local file="$2"
    local owner="${3:-root:root}"
    local perms="${4:-644}"
    
    echo "$content" | sudo_n tee "$file" > /dev/null || return 1
    sudo_n chown "$owner" "$file" || return 1
    sudo_n chmod "$perms" "$file" || return 1
}

# サービス管理
manage_service() {
    local action="$1"
    local service="$2"
    
    case $action in
        start|stop|restart|enable|disable|status)
            sudo_n systemctl "$action" "$service"
            ;;
        reload)
            sudo_n systemctl reload-or-restart "$service"
            ;;
        *)
            echo "Unknown action: $action" >&2
            return 1
            ;;
    esac
}

# パッケージインストール（apt）
install_packages() {
    local packages=("$@")
    
    sudo_n apt-get update || return 1
    sudo_n apt-get install -y "${packages[@]}" || return 1
}

# スナップパッケージインストール
install_snap() {
    local package="$1"
    local channel="${2:-stable}"
    local classic="${3:-}"
    
    if [[ "$classic" == "classic" ]]; then
        sudo_n snap install "$package" --channel="$channel" --classic
    else
        sudo_n snap install "$package" --channel="$channel"
    fi
}

# ファイル/ディレクトリの存在確認（sudo権限）
sudo_exists() {
    sudo_n test -e "$1"
}

# systemdデーモンリロード
reload_systemd() {
    sudo_n systemctl daemon-reload
}

# ネットワークインターフェース管理
manage_network() {
    local action="$1"
    local interface="$2"
    
    case $action in
        up|down)
            sudo_n ip link set "$interface" "$action"
            ;;
        restart)
            sudo_n ip link set "$interface" down
            sleep 1
            sudo_n ip link set "$interface" up
            ;;
        *)
            echo "Unknown action: $action" >&2
            return 1
            ;;
    esac
}

# iptables/nftables管理
manage_firewall() {
    local action="$1"
    shift
    
    case $action in
        add-rule)
            sudo_n iptables "$@"
            ;;
        save)
            sudo_n iptables-save > /tmp/iptables.rules
            sudo_n mv /tmp/iptables.rules /etc/iptables/rules.v4
            ;;
        restore)
            sudo_n iptables-restore < /etc/iptables/rules.v4
            ;;
        *)
            echo "Unknown action: $action" >&2
            return 1
            ;;
    esac
}

# プロセス管理
kill_process_by_name() {
    local process_name="$1"
    sudo_n pkill -f "$process_name"
}

# マウント操作
mount_device() {
    local device="$1"
    local mount_point="$2"
    local fs_type="${3:-ext4}"
    
    create_directory "$mount_point" || return 1
    sudo_n mount -t "$fs_type" "$device" "$mount_point"
}

# ユーザー/グループ管理
add_user_to_group() {
    local user="$1"
    local group="$2"
    
    sudo_n usermod -aG "$group" "$user"
}