#!/bin/bash

set -e

echo "=== Harbor証明書修正デプロイメント ==="

# SSH known_hosts クリーンアップ
echo "SSH known_hostsをクリーンアップ中..."
ssh-keygen -f "$HOME/.ssh/known_hosts" -R '192.168.122.10' 2>/dev/null || true

# k8sクラスタ接続確認
echo "k8sクラスタ接続を確認中..."
if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
    echo "エラー: k8sクラスタに接続できません"
    echo "Phase 3のk8sクラスタ構築を先に完了してください"
    echo "注意: このスクリプトはUbuntuホストマシンで実行してください（WSL2不可）"
    exit 1
fi

echo "✓ k8sクラスタ接続OK"

echo "1. IP SANを含むHarbor証明書を適用中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl apply -f -' < ../../infra/cert-manager/harbor-certificate.yaml

echo "2. Harbor証明書の準備完了を待機中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl wait --for=condition=Ready certificate/harbor-tls-cert -n harbor --timeout=120s'

echo "3. Harbor CA信頼DaemonSetを適用中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl apply -f -' < ../../infra/harbor-ca-trust.yaml

echo "4. Harbor CA信頼DaemonSetの準備完了を待機中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl rollout status daemonset/harbor-ca-trust -n kube-system --timeout=300s'

echo "5. 証明書デプロイメントの確認中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get certificate harbor-tls-cert -n harbor -o wide'
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret harbor-tls-secret -n harbor'

echo "6. DaemonSetの状態確認中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get daemonset harbor-ca-trust -n kube-system'
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get pods -n kube-system -l app=harbor-ca-trust'

echo "=== Harbor証明書修正が正常に完了しました ==="

echo ""
echo "次のステップ:"
echo "1. 既存のGitHub Actionsランナーを再起動して新しい証明書信頼を適用"
echo "2. docker loginをテスト: docker login 192.168.122.100 -u admin"
echo "3. 証明書にはharbor.localと192.168.122.100の両方がSANに含まれています"

echo ""
echo "修正の確認方法:"
echo "kubectl exec -it <github-actions-runner-pod> -- docker login 192.168.122.100 -u admin"