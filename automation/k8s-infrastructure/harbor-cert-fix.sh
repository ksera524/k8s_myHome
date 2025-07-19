#!/bin/bash

set -e

echo "=== Harbor証明書修正 + GitHub Actions対応自動化 ==="

# SSH known_hosts クリーンアップ
echo "SSH known_hostsをクリーンアップ中..."
ssh-keygen -f "$HOME/.ssh/known_hosts" -R '192.168.122.10' 2>/dev/null || true
ssh-keygen -f "$HOME/.ssh/known_hosts" -R '192.168.122.11' 2>/dev/null || true  
ssh-keygen -f "$HOME/.ssh/known_hosts" -R '192.168.122.12' 2>/dev/null || true

# k8sクラスタ接続確認
echo "k8sクラスタ接続を確認中..."
if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
    echo "エラー: k8sクラスタに接続できません"
    echo "Phase 3のk8sクラスタ構築を先に完了してください"
    echo "注意: このスクリプトはUbuntuホストマシンで実行してください（WSL2不可）"
    exit 1
fi

echo "✓ k8sクラスタ接続OK"

# Harborのデプロイ状況確認
echo "Harbor namespaceとデプロイ状況を確認中..."
if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get namespace harbor' >/dev/null 2>&1; then
    echo "⚠️  Harbor namespaceが見つかりません"
    echo "Phase 4のApp of Apps (ArgoCD)でHarborがデプロイされるまで待機中..."
    
    # 最大5分間Harborデプロイを待機
    for i in {1..30}; do
        echo "  待機中... ($i/30)"
        sleep 10
        if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get namespace harbor' >/dev/null 2>&1; then
            echo "✓ Harbor namespaceが作成されました"
            break
        fi
        if [ $i -eq 30 ]; then
            echo "❌ Harbor namespace作成のタイムアウト"
            echo "ArgoCD経由でのHarborデプロイが完了していない可能性があります"
            echo "手動確認: kubectl get applications -n argocd"
            exit 1
        fi
    done
fi

# Harborポッドの稼働確認
echo "Harborポッドの稼働状況を確認中..."
if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get pods -n harbor | grep harbor-core | grep Running' >/dev/null 2>&1; then
    echo "⚠️  HarborのCoreポッドがまだ稼働していません"
    echo "Harborポッドの起動を待機中..."
    
    # 最大5分間Harbor稼働を待機
    for i in {1..30}; do
        echo "  ポッド起動待機... ($i/30)"
        sleep 10
        if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get pods -n harbor | grep harbor-core | grep Running' >/dev/null 2>&1; then
            echo "✓ Harbor Coreポッドが稼働中です"
            break
        fi
        if [ $i -eq 30 ]; then
            echo "❌ Harbor稼働のタイムアウト"
            echo "Harborポッドが正常に起動していない可能性があります"
            echo "手動確認: kubectl get pods -n harbor"
            exit 1
        fi
    done
fi

echo "✓ Harbor稼働確認完了"

echo "1. 既存のHarbor証明書を削除し、新しいIP SAN証明書を適用中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl delete certificate harbor-tls-cert -n harbor --ignore-not-found=true'
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl delete secret harbor-tls-secret -n harbor --ignore-not-found=true'
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl apply -f -' < ../../infra/cert-manager/harbor-certificate.yaml

echo "2. Harbor証明書の準備完了を待機中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl wait --for=condition=Ready certificate/harbor-tls-cert -n harbor --timeout=120s'

echo "2.1. 新しい証明書を適用するためHarborコンテナを再起動中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl rollout restart deployment/harbor-core -n harbor'
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl rollout restart deployment/harbor-portal -n harbor'
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl rollout restart deployment/harbor-registry -n harbor'
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl rollout status deployment/harbor-core -n harbor --timeout=300s'

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

# 7. Worker ノードのDocker/containerd設定（GitHub Actions対応）
echo "7. Worker ノードのinsecure registry設定中..."
for worker in 192.168.122.11 192.168.122.12; do
    echo "  - Worker $worker設定中..."
    
    # Docker daemon.json設定
    ssh -o StrictHostKeyChecking=no k8suser@$worker 'sudo mkdir -p /etc/docker && echo "{\"insecure-registries\": [\"192.168.122.100\"]}" | sudo tee /etc/docker/daemon.json' || echo "Docker設定失敗: $worker"
    
    # containerd設定
    ssh -o StrictHostKeyChecking=no k8suser@$worker 'sudo mkdir -p /etc/containerd && sudo tee /etc/containerd/config.toml > /dev/null << EOF
version = 2

[plugins."io.containerd.grpc.v1.cri".registry]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."192.168.122.100"]
      endpoint = ["http://192.168.122.100", "https://192.168.122.100"]
  [plugins."io.containerd.grpc.v1.cri".registry.configs]
    [plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.122.100".tls]
      insecure_skip_verify = true
EOF' || echo "containerd設定失敗: $worker"
    
    # サービス再起動
    ssh -o StrictHostKeyChecking=no k8suser@$worker 'sudo systemctl restart containerd && sleep 3' || echo "containerd再起動失敗: $worker"
    
    echo "  ✓ Worker $worker設定完了"
done

# 8. GitHub Actions Runner の再起動
echo "8. GitHub Actions Runner の再起動中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get pods -n arc-systems | grep runner' | while read line; do
    pod_name=$(echo $line | awk '{print $1}')
    if [[ $pod_name =~ .*-runners-.* ]]; then
        echo "  - ランナーポッド再起動: $pod_name"
        ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl delete pod $pod_name -n arc-systems" || echo "ポッド削除失敗: $pod_name"
    fi
done

echo "  - 新しいランナーポッドの起動を待機中..."
sleep 15

# 9. HTTP Ingress追加（フォールバック用）
echo "9. Harbor イメージプルシークレットを作成中..."
# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# create-harbor-secrets.sh スクリプトを実行
if [[ -f "$SCRIPT_DIR/create-harbor-secrets.sh" ]]; then
    echo "  - Harborイメージプルシークレット作成スクリプトを実行中..."
    bash "$SCRIPT_DIR/create-harbor-secrets.sh"
else
    echo "  ⚠️  create-harbor-secrets.sh が見つかりません。手動作成が必要です。"
fi

echo "10. Harbor HTTP Ingressを追加中..."
# 既存のharbor-http-ingressが存在するかチェック
if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get ingress harbor-http-ingress -n harbor' >/dev/null 2>&1; then
    echo "  ⚠️  harbor-http-ingress が既に存在します。スキップします。"
elif ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get ingress harbor-http-ingress-patch -n harbor' >/dev/null 2>&1; then
    echo "  ⚠️  harbor-http-ingress-patch が既に存在します。同じ機能のため追加をスキップします。"
else
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl apply -f -' << 'EOF' || echo "HTTP Ingress適用失敗"
# Harbor用一時的HTTP Ingress設定
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: harbor-http-ingress
  namespace: harbor
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"  # HTTPアクセス許可
spec:
  ingressClassName: nginx
  rules:
  - http:  # ホスト名なしでIPアクセス許可
      paths:
      - backend:
          service:
            name: harbor-core
            port:
              number: 80
        path: /api/
        pathType: Prefix
      - backend:
          service:
            name: harbor-core
            port:
              number: 80
        path: /service/
        pathType: Prefix
      - backend:
          service:
            name: harbor-core
            port:
              number: 80
        path: /v2/
        pathType: Prefix
      - backend:
          service:
            name: harbor-core
            port:
              number: 80
        path: /chartrepo/
        pathType: Prefix
      - backend:
          service:
            name: harbor-core
            port:
              number: 80
        path: /c/
        pathType: Prefix
      - backend:
          service:
            name: harbor-portal
            port:
              number: 80
        path: /
        pathType: Prefix
EOF
fi

echo "=== Harbor証明書修正 + GitHub Actions対応が正常に完了しました ==="

echo ""
echo "✅ 完了した設定:"
echo "1. IP SAN（192.168.122.100）を含むHarbor証明書"
echo "2. CA信頼配布DaemonSet（全ノード対応）"
echo "3. Worker ノードのinsecure registry設定"
echo "4. GitHub Actions Runner の再起動"
echo "5. Harbor イメージプルシークレット（全ネームスペース）"
echo "6. Harbor HTTP Ingress（フォールバック用）"

echo ""
echo "✅ GitHub Actionsで利用可能:"
echo "- crane + --insecure フラグでの確実なpush"
echo "- DNS解決: 192.168.122.100 harbor.local"
echo "- 認証: admin / Harbor12345"

echo ""
echo "テスト方法:"
echo "kubectl exec -it \$(kubectl get pods -n arc-systems | grep runner | head -1 | awk '{print \$1}') -n arc-systems -- curl -k https://192.168.122.100/v2/_catalog -u \${HARBOR_USERNAME:-admin}:\${HARBOR_PASSWORD:-Harbor12345}"