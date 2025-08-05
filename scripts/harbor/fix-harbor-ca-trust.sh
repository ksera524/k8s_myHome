#!/bin/bash

# Harbor CA信頼配布スクリプト
# GitHub Actions Runner用のHarbor証明書問題を解決

set -euo pipefail

echo "=== Harbor CA信頼配布開始 ==="

# Harbor証明書をarc-systemsにコピー（既存の処理を確認）
echo "Harbor証明書の状態確認..."
if ! kubectl get secret harbor-tls-secret -n arc-systems >/dev/null 2>&1; then
    echo "Harbor証明書をarc-systemsにコピー中..."
    kubectl get secret harbor-tls-secret -n harbor -o yaml | \
        sed 's/namespace: harbor/namespace: arc-systems/' | \
        kubectl apply -f -
fi

# システム証明書ストアへの配布DaemonSet作成
echo "Harbor CA信頼DaemonSet作成中..."
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: harbor-ca-trust
  namespace: kube-system
  labels:
    app: harbor-ca-trust
spec:
  selector:
    matchLabels:
      app: harbor-ca-trust
  template:
    metadata:
      labels:
        app: harbor-ca-trust
    spec:
      hostNetwork: true
      serviceAccountName: harbor-ca-trust
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
          echo "Harbor CA証明書をシステム証明書ストアに配布中..."
          
          # Harbor証明書を取得
          cp /etc/harbor-certs/tls.crt /tmp/harbor.crt
          
          # システム証明書ストアに追加
          cp /tmp/harbor.crt /host-certs/harbor.crt
          
          # Docker証明書ディレクトリに配布
          mkdir -p /host-docker-certs/192.168.122.100
          cp /tmp/harbor.crt /host-docker-certs/192.168.122.100/ca.crt
          
          # 証明書更新処理
          if command -v chroot >/dev/null 2>&1; then
            chroot /host-root update-ca-certificates 2>/dev/null || true
          fi
          
          echo "Harbor CA証明書配布完了"
          
        volumeMounts:
        - name: harbor-certs
          mountPath: /etc/harbor-certs
          readOnly: true
        - name: host-certs
          mountPath: /host-certs
        - name: host-docker-certs
          mountPath: /host-docker-certs
        - name: host-root
          mountPath: /host-root
        securityContext:
          privileged: true
      containers:
      - name: certificate-monitor
        image: alpine:latest
        command:
        - /bin/sh
        - -c
        - |
          echo "Harbor CA証明書監視開始..."
          while true; do
            if [ -f "/etc/harbor-certs/tls.crt" ]; then
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
            cpu: 50m
            memory: 64Mi
      volumes:
      - name: harbor-certs
        secret:
          secretName: harbor-tls-secret
      - name: host-certs
        hostPath:
          path: /etc/ssl/certs
          type: DirectoryOrCreate
      - name: host-docker-certs
        hostPath:
          path: /etc/docker/certs.d
          type: DirectoryOrCreate
      - name: host-root
        hostPath:
          path: /
          type: Directory
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: harbor-ca-trust
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: harbor-ca-trust
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: harbor-ca-trust
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: harbor-ca-trust
subjects:
- kind: ServiceAccount
  name: harbor-ca-trust
  namespace: kube-system
EOF

echo "DaemonSet状態確認中..."
kubectl get daemonset harbor-ca-trust -n kube-system

echo "=== Harbor CA信頼配布完了 ==="
echo "GitHub Actions Runnerが再起動されると、Harbor証明書が自動的に信頼されます"