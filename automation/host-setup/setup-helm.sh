#!/bin/bash

# Helm セットアップスクリプト 
# Host Setup段階でHelmとよく使用されるHelm repositoryを準備

set -euo pipefail

# スクリプトディレクトリ取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 共通色設定スクリプトを読み込み
source "$SCRIPT_DIR/../scripts/common-colors.sh"

print_status "=== Helm セットアップ ==="

# ローカルホストでのHelm確認・インストール
print_status "ローカルホストでのHelm確認・インストール中..."
if ! command -v helm &> /dev/null; then
    print_debug "Helmをインストール中..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    print_status "✓ Helm ローカルインストール完了"
else
    print_debug "✓ Helm ローカル既にインストール済み"
fi

# k8s control-planeでのHelm確認・インストール
print_status "Kubernetesクラスター(control-plane)でのHelm確認・インストール中..."

if ping -c 1 192.168.122.10 &> /dev/null; then
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
    if ! command -v helm &> /dev/null; then
        echo "Helmをインストール中..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
        echo "✓ Helm リモートインストール完了"
    else
        echo "✓ Helm リモート既にインストール済み"
    fi
EOF
    print_status "✓ Kubernetes control-planeでのHelm確認完了"
else
    print_warning "Kubernetesクラスターに接続できません (192.168.122.10)"
    print_debug "後でplatform段階でHelmがインストールされます"
fi

# 共通で使用されるHelm repositoryを追加
print_status "共通Helm repositoryを準備中..."

if ping -c 1 192.168.122.10 &> /dev/null; then
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
    # External Secrets Operator repository
    if ! helm repo list | grep -q external-secrets; then
        echo "External Secrets repository追加中..."
        helm repo add external-secrets https://charts.external-secrets.io
    fi
    
    # Harbor repository  
    if ! helm repo list | grep -q harbor; then
        echo "Harbor repository追加中..."
        helm repo add harbor https://helm.goharbor.io
    fi
    
    # Actions Runner Controller repository (将来のため)
    if ! helm repo list | grep -q actions-runner-controller; then
        echo "Actions Runner Controller repository追加中..."
        helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
    fi
    
    # Repository更新
    echo "Repository情報を更新中..."
    helm repo update
    
    echo "✓ Helm repository準備完了"
    helm repo list
EOF
    print_status "✓ 共通Helm repository準備完了"
else
    print_warning "Kubernetesクラスターに接続できないため、repository準備をスキップ"
    print_debug "後でplatform段階でrepositoryが追加されます"
fi

print_status "=== Helm セットアップ完了 ==="
print_debug "次のステップ: automation/infrastructure/ でKubernetesクラスター構築"

exit 0