#!/bin/bash

set -e

echo "=== cert-manager CA証明書自動化セットアップ ==="

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. CA証明書とキーが存在するか確認、なければ生成
CA_CERT_PATH="$SCRIPT_DIR/../../certs/ca-cert.pem"
CA_KEY_PATH="$SCRIPT_DIR/../../certs/ca-key.pem"

if [[ ! -f "$CA_CERT_PATH" ]] || [[ ! -f "$CA_KEY_PATH" ]]; then
    echo "CA証明書とキーを生成中..."
    mkdir -p "$SCRIPT_DIR/../../certs"
    
    # CA設定ファイル作成
    cat > "$SCRIPT_DIR/../../certs/ca.conf" << 'EOF'
[ req ]
default_bits = 4096
prompt = no
distinguished_name = req_distinguished_name
x509_extensions = v3_ca

[ req_distinguished_name ]
C = JP
ST = Tokyo
L = Tokyo
O = k8s_myHome
OU = Infrastructure
CN = k8s-myHome Internal CA

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical,CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF

    # CA証明書とキー生成
    openssl req -x509 -new -nodes \
        -keyout "$CA_KEY_PATH" \
        -out "$CA_CERT_PATH" \
        -days 3650 \
        -config "$SCRIPT_DIR/../../certs/ca.conf"
    
    echo "✓ CA証明書とキー生成完了"
fi

# 2. Kubernetes SecretとしてCA証明書を適用
echo "CA証明書をKubernetes Secretとして適用中..."

CA_CERT_B64=$(base64 -w 0 "$CA_CERT_PATH")
CA_KEY_B64=$(base64 -w 0 "$CA_KEY_PATH")

# CA Secret適用
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << EOF
kubectl apply -f - << 'EOYAML'
apiVersion: v1
kind: Secret
metadata:
  name: ca-key-pair
  namespace: cert-manager
type: Opaque
data:
  tls.crt: $CA_CERT_B64
  tls.key: $CA_KEY_B64
EOYAML
EOF

echo "✓ CA Secret適用完了"

# 3. CA Issuer適用
echo "CA ClusterIssuer適用中..."

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
kubectl apply -f - << 'EOYAML'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ca-cluster-issuer
spec:
  ca:
    secretName: ca-key-pair
EOYAML
EOF

echo "✓ CA ClusterIssuer適用完了"

# 4. CA信頼配布DaemonSet適用
echo "CA信頼配布DaemonSet適用中..."

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 'kubectl apply -f -' << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: ca-trust-script
  namespace: kube-system
data:
  install-ca.sh: |
    #!/bin/bash
    set -e
    
    echo "CA証明書信頼設定を開始..."
    
    # CA証明書をcert-managerから取得
    while ! kubectl get secret ca-key-pair -n cert-manager >/dev/null 2>&1; do
      echo "CA秘密キーペアの作成を待機中..."
      sleep 10
    done
    
    # CA証明書をcert-managerのSecretから抽出
    kubectl get secret ca-key-pair -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/k8s-ca.crt
    
    # システムの信頼ストアにCA証明書をインストール
    cp /tmp/k8s-ca.crt /etc/ssl/certs/k8s-ca.crt
    update-ca-certificates
    
    # Docker用の証明書設定 (Harbor IP)
    mkdir -p /etc/docker/certs.d/192.168.122.100
    cp /tmp/k8s-ca.crt /etc/docker/certs.d/192.168.122.100/ca.crt
    
    # Docker用の証明書設定 (Harbor DNS)
    mkdir -p /etc/docker/certs.d/harbor.local
    cp /tmp/k8s-ca.crt /etc/docker/certs.d/harbor.local/ca.crt
    
    # containerdの設定更新
    mkdir -p /etc/containerd/certs.d/192.168.122.100
    cat > /etc/containerd/certs.d/192.168.122.100/hosts.toml << EOFINNER
    server = "https://192.168.122.100"
    
    [host."https://192.168.122.100"]
      ca = "/tmp/k8s-ca.crt"
      skip_verify = false
EOFINNER
    
    # containerd再起動
    systemctl restart containerd || true
    
    echo "CA証明書信頼設定完了"

---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ca-trust-daemonset
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: ca-trust
  template:
    metadata:
      labels:
        app: ca-trust
    spec:
      hostNetwork: true
      hostPID: true
      containers:
      - name: ca-trust
        image: bitnami/kubectl:latest
        command: ["/bin/bash"]
        args: ["/scripts/install-ca.sh"]
        securityContext:
          privileged: true
        volumeMounts:
        - name: host-etc-ssl
          mountPath: /etc/ssl
        - name: host-etc-docker
          mountPath: /etc/docker
        - name: host-etc-containerd
          mountPath: /etc/containerd
        - name: ca-trust-script
          mountPath: /scripts
        - name: host-usr-local-share
          mountPath: /usr/local/share
        env:
        - name: KUBECONFIG
          value: "/etc/kubernetes/admin.conf"
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi" 
            cpu: "100m"
      volumes:
      - name: host-etc-ssl
        hostPath:
          path: /etc/ssl
          type: DirectoryOrCreate
      - name: host-etc-docker
        hostPath:
          path: /etc/docker
          type: DirectoryOrCreate
      - name: host-etc-containerd
        hostPath:
          path: /etc/containerd
          type: DirectoryOrCreate
      - name: ca-trust-script
        configMap:
          name: ca-trust-script
          defaultMode: 0755
      - name: host-usr-local-share
        hostPath:
          path: /usr/local/share
          type: DirectoryOrCreate
      tolerations:
      - operator: Exists
      restartPolicy: Always
EOF

echo "✓ CA信頼配布DaemonSet適用完了"

# 5. Harbor証明書をCA Issuerベースに更新
echo "Harbor証明書をCA Issuerベースに更新中..."

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
# 既存証明書削除
kubectl delete certificate harbor-tls-cert -n harbor --ignore-not-found=true
kubectl delete secret harbor-tls-secret -n harbor --ignore-not-found=true

# 新しいCA Issuerベース証明書適用
kubectl apply -f - << 'EOYAML'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: harbor-tls-cert
  namespace: harbor
spec:
  secretName: harbor-tls-secret
  issuerRef:
    name: ca-cluster-issuer
    kind: ClusterIssuer
  commonName: harbor.local
  dnsNames:
  - harbor.local
  ipAddresses:
  - "192.168.122.100"
  usages:
  - digital signature
  - key encipherment
  - server auth
EOYAML

# 証明書準備完了待機
kubectl wait --for=condition=Ready certificate/harbor-tls-cert -n harbor --timeout=120s
EOF

echo "✓ Harbor証明書更新完了"

# 6. Harbor Pod再起動
echo "Harbor Pod再起動中..."
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
kubectl rollout restart deployment/harbor-core -n harbor
kubectl rollout restart deployment/harbor-portal -n harbor
kubectl rollout restart deployment/harbor-registry -n harbor
kubectl rollout status deployment/harbor-core -n harbor --timeout=300s
EOF

echo "✅ cert-manager CA証明書自動化セットアップ完了"
echo ""
echo "🔑 内部CAによる証明書管理が有効化されました"
echo "📋 Harbor証明書にIP SAN (192.168.122.100) が含まれ、GitHub ActionsのContainer Registryアクセスが可能です"