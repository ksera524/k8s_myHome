#!/bin/bash

# Harbor CA証明書配布設定スクリプト
# GitHub Actions RunnerにHarbor証明書を配布

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_status "=== Harbor CA証明書配布設定 ==="

# Harbor証明書をarc-systemsネームスペースにコピー
print_status "Harbor証明書をarc-systemsネームスペースにコピー中..."

if kubectl get secret harbor-tls-secret -n harbor >/dev/null 2>&1; then
    # 既存のSecretを削除
    kubectl delete secret harbor-ca-cert -n arc-systems --ignore-not-found=true
    
    # 証明書データを取得
    HARBOR_CERT=$(kubectl get secret harbor-tls-secret -n harbor -o jsonpath='{.data.tls\.crt}')
    
    # arc-systemsネームスペースに新しいSecretを作成
    kubectl create secret generic harbor-ca-cert -n arc-systems \
        --from-literal=ca.crt="$(echo $HARBOR_CERT | base64 -d)"
    
    print_status "✅ Harbor証明書をarc-systemsにコピー完了"
else
    print_error "Harbor TLS証明書が見つかりません"
    exit 1
fi

# CA配布DaemonSetを適用
print_status "Harbor CA配布DaemonSetを適用中..."
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: harbor-ca-distribution
  namespace: arc-systems
  labels:
    app: harbor-ca-distribution
spec:
  selector:
    matchLabels:
      app: harbor-ca-distribution
  template:
    metadata:
      labels:
        app: harbor-ca-distribution
    spec:
      tolerations:
      - operator: Exists
        effect: NoSchedule
      initContainers:
      - name: ca-installer
        image: alpine:latest
        command:
        - /bin/sh
        - -c
        - |
          echo "Harbor CA証明書配布を開始..."
          
          # Docker証明書ディレクトリに配布
          mkdir -p /host-docker-certs/192.168.122.100
          cp /etc/harbor-certs/ca.crt /host-docker-certs/192.168.122.100/ca.crt
          
          echo "Harbor CA証明書配布完了"
          echo "証明書内容:"
          openssl x509 -in /etc/harbor-certs/ca.crt -text -noout | grep -A 2 "Subject Alternative Name" || echo "SAN情報なし"
          
        volumeMounts:
        - name: harbor-certs
          mountPath: /etc/harbor-certs
          readOnly: true
        - name: host-docker-certs
          mountPath: /host-docker-certs
        securityContext:
          privileged: true
      containers:
      - name: certificate-monitor
        image: alpine:latest
        command:
        - /bin/sh
        - -c
        - |
          echo "Harbor CA証明書監視を開始..."
          while true; do
            if [ -f "/etc/harbor-certs/ca.crt" ]; then
              echo "Harbor証明書監視中: \$(date)"
            else
              echo "Harbor証明書が見つかりません"
            fi
            sleep 3600
          done
        volumeMounts:
        - name: harbor-certs
          mountPath: /etc/harbor-certs
          readOnly: true
        resources:
          requests:
            cpu: 10m
            memory: 32Mi
          limits:
            cpu: 100m
            memory: 64Mi
      volumes:
      - name: harbor-certs
        secret:
          secretName: harbor-ca-cert
      - name: host-docker-certs
        hostPath:
          path: /etc/docker/certs.d
          type: DirectoryOrCreate
EOF

print_status "✅ Harbor CA配布DaemonSet適用完了"

# DaemonSetの状態確認
print_status "DaemonSet状態確認中..."
kubectl get daemonset harbor-ca-distribution -n arc-systems

print_status "=== Harbor CA証明書配布設定完了 ==="
print_status "GitHub Actions Runnerが再起動されると、Harbor証明書が自動的に配布されます"