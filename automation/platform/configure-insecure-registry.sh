#!/bin/bash

# Insecure Registry設定自動化スクリプト
# Harbor内部IPアクセス用の設定を全ワーカーノードに適用

set -euo pipefail

HARBOR_IP="192.168.122.100"
HARBOR_PORT="80"

echo "=== Harbor Insecure Registry設定を開始 ==="

# 各ワーカーノードでInsecure Registry設定を適用
configure_node() {
    local node_ip=$1
    local node_name=$2
    
    echo "[$node_name] Insecure Registry設定を適用中..."
    
    # containerd設定ファイルのバックアップと更新
    ssh k8suser@$node_ip << 'EOF'
        # containerd設定ディレクトリ作成
        sudo -n mkdir -p /etc/containerd/certs.d/192.168.122.100
        
        # Insecure Registry設定作成
        sudo -n tee /etc/containerd/certs.d/192.168.122.100/hosts.toml > /dev/null << 'CONFIG'
[host."http://192.168.122.100"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
  plain_http = true
CONFIG
        
        # containerd再起動
        sudo -n systemctl restart containerd
        
        echo "containerd設定完了: $(hostname)"
EOF
    
    if [ $? -eq 0 ]; then
        echo "[$node_name] 設定完了"
    else
        echo "[$node_name] 設定エラー" >&2
        return 1
    fi
}

# 設定対象ノード一覧
WORKER_NODES=(
    "192.168.122.11:worker1"
    "192.168.122.12:worker2"
)

# Control Planeノードも対象に含める
CONTROL_PLANE="192.168.122.10:control-plane"

echo "=== 全ノードでInsecure Registry設定を実行 ==="

# Control Planeノード設定
IFS=':' read -r node_ip node_name <<< "$CONTROL_PLANE"
configure_node "$node_ip" "$node_name"

# ワーカーノード設定
for node_info in "${WORKER_NODES[@]}"; do
    IFS=':' read -r node_ip node_name <<< "$node_info"
    configure_node "$node_ip" "$node_name"
done

echo "=== Docker daemon.json設定（必要に応じて実行） ==="

# Docker使用時のInsecure Registry設定も追加
configure_docker_daemon() {
    local node_ip=$1
    local node_name=$2
    
    echo "[$node_name] Docker daemon.json設定..."
    
    ssh k8suser@$node_ip << 'EOF'
        # Docker daemon.json設定
        sudo -n mkdir -p /etc/docker
        
        # 既存設定確認と統合
        if [ -f /etc/docker/daemon.json ]; then
            sudo -n cp /etc/docker/daemon.json /etc/docker/daemon.json.backup
        fi
        
        # Insecure Registry設定追加
        sudo -n tee /etc/docker/daemon.json > /dev/null << 'DOCKER_CONFIG'
{
  "insecure-registries": [
    "192.168.122.100",
    "192.168.122.100:80",
    "192.168.122.100:5000"
  ],
  "registry-mirrors": []
}
DOCKER_CONFIG
        
        # Docker再起動（Dockerが実行中の場合のみ）
        if systemctl is-active --quiet docker; then
            sudo -n systemctl restart docker
            echo "Docker再起動完了: $(hostname)"
        else
            echo "Docker未実行: $(hostname)"
        fi
EOF
}

echo "Docker daemon.json設定も実行しますか? (y/N)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    # Control Planeノード
    IFS=':' read -r node_ip node_name <<< "$CONTROL_PLANE"
    configure_docker_daemon "$node_ip" "$node_name"
    
    # ワーカーノード
    for node_info in "${WORKER_NODES[@]}"; do
        IFS=':' read -r node_ip node_name <<< "$node_info"
        configure_docker_daemon "$node_ip" "$node_name"
    done
fi

echo "=== 設定確認 ==="

# 設定確認
verify_configuration() {
    local node_ip=$1
    local node_name=$2
    
    echo "[$node_name] 設定確認..."
    
    ssh k8suser@$node_ip << 'EOF'
        echo "=== containerd設定確認 ==="
        if [ -f /etc/containerd/certs.d/192.168.122.100/hosts.toml ]; then
            echo "✓ containerd Insecure Registry設定あり"
            cat /etc/containerd/certs.d/192.168.122.100/hosts.toml
        else
            echo "✗ containerd設定なし"
        fi
        
        echo "=== Docker設定確認 ==="
        if [ -f /etc/docker/daemon.json ]; then
            echo "✓ Docker daemon.json設定あり"
            cat /etc/docker/daemon.json
        else
            echo "- Docker設定なし"
        fi
        
        echo "=== サービス状態確認 ==="
        systemctl is-active containerd || echo "containerd停止中"
        if command -v docker >/dev/null 2>&1; then
            systemctl is-active docker || echo "docker停止中"
        fi
EOF
}

echo "全ノードの設定を確認中..."
# Control Planeノード確認
IFS=':' read -r node_ip node_name <<< "$CONTROL_PLANE"
verify_configuration "$node_ip" "$node_name"

# ワーカーノード確認
for node_info in "${WORKER_NODES[@]}"; do
    IFS=':' read -r node_ip node_name <<< "$node_info"
    verify_configuration "$node_ip" "$node_name"
done

echo "=== Insecure Registry設定完了 ==="
echo "Harbor URL: http://$HARBOR_IP"
echo "使用方法:"
echo "  docker pull $HARBOR_IP/library/image:tag"
echo "  docker push $HARBOR_IP/library/image:tag"