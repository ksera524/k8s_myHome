#!/bin/bash

# Harbor Registry修正スクリプト - make all後の問題修正用
# シンプルで確実な一行修正

echo "🔧 Harbor Registry設定修正開始..."

# 全ノードでcontainerdのinsecure registry設定修正
for NODE_IP in "192.168.122.10" "192.168.122.11" "192.168.122.12"; do
  echo "📡 Node $NODE_IP 設定中..."
  ssh -o StrictHostKeyChecking=no k8suser@$NODE_IP 'sudo mkdir -p /etc/containerd/certs.d/192.168.122.100 && sudo tee /etc/containerd/certs.d/192.168.122.100/hosts.toml > /dev/null << EOF
server = "http://192.168.122.100"
EOF
sudo sed -i "s/config_path = \"\"/config_path = \"\/etc\/containerd\/certs.d\"/g" /etc/containerd/config.toml
sudo systemctl restart containerd'
  echo "✅ Node $NODE_IP 完了"
done

echo "🔄 Slackポッド再起動中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl delete pod -n sandbox -l app=slack'

echo "⏳ ポッド起動待機中..."
sleep 30

echo "📊 最終状態確認:"
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get pods -n sandbox'

echo "✨ Harbor Registry修正完了！"