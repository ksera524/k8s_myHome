# 🛠️ 開発環境セットアップガイド

## 概要

k8s_myHomeプロジェクトの開発環境構築手順と、効率的な開発ワークフローについて説明します。

## 開発環境要件

### ハードウェア要件
- **CPU**: 8コア以上（仮想化対応）
- **メモリ**: 16GB以上（推奨: 32GB）
- **ストレージ**: 100GB以上のSSD
- **ネットワーク**: 安定したインターネット接続

### ソフトウェア要件
```bash
# 必須ツール
- Git 2.34+
- Docker 24.0+
- kubectl 1.29+
- Terraform 1.6+
- Helm 3.13+
- VS Code / IntelliJ IDEA

# 推奨ツール
- k9s (Kubernetes TUI)
- kubectx/kubens
- stern (マルチPodログ)
- jq (JSON処理)
- yq (YAML処理)
```

## ローカル開発環境構築

### 1. プロジェクトセットアップ

```bash
# リポジトリクローン
git clone https://github.com/ksera524/k8s_myHome.git
cd k8s_myHome

# ブランチ作成
git checkout -b feature/your-feature

# 依存関係確認
./scripts/check-dependencies.sh
```

### 2. 開発用Kubernetesクラスター

#### オプション1: 本番相当環境（推奨）
```bash
# フル環境構築
make all

# kubeconfig設定
export KUBECONFIG=$HOME/.kube/config
kubectl config use-context k8s-myhome
```

#### オプション2: 軽量環境（Kind）
```bash
# Kindクラスター作成
cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: k8s-myhome-dev
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
  - containerPort: 443
    hostPort: 443
- role: worker
- role: worker
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
EOF

# MetalLB設定（Kind用）
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s

# IPアドレスプール設定
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: kind-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.18.255.200-172.18.255.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: kind-advertisement
  namespace: metallb-system
EOF
```

#### オプション3: Minikube
```bash
# Minikube起動
minikube start \
  --nodes=3 \
  --cpus=2 \
  --memory=4096 \
  --driver=virtualbox \
  --kubernetes-version=v1.29.0

# アドオン有効化
minikube addons enable ingress
minikube addons enable metrics-server
minikube addons enable dashboard
```

### 3. 開発ツールセットアップ

```bash
# kubectx/kubens インストール
brew install kubectx  # macOS
# または
sudo apt install kubectx  # Ubuntu

# k9s インストール
brew install k9s  # macOS
# または
curl -sS https://webinstall.dev/k9s | bash

# stern インストール
brew install stern  # macOS
# または
wget https://github.com/stern/stern/releases/download/v1.28.0/stern_1.28.0_linux_amd64.tar.gz

# ArgoCD CLI
brew install argocd  # macOS
# または
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
```

### 4. IDE設定

#### VS Code拡張機能
```json
// .vscode/extensions.json
{
  "recommendations": [
    "ms-kubernetes-tools.vscode-kubernetes-tools",
    "redhat.vscode-yaml",
    "hashicorp.terraform",
    "ms-azuretools.vscode-docker",
    "golang.go",
    "rust-lang.rust-analyzer",
    "github.copilot"
  ]
}
```

#### VS Code設定
```json
// .vscode/settings.json
{
  "yaml.schemas": {
    "kubernetes": ["manifests/**/*.yaml"],
    "https://json.schemastore.org/github-workflow.json": ".github/workflows/*.yml"
  },
  "yaml.customTags": [
    "!And",
    "!If",
    "!Not",
    "!Equals",
    "!Or",
    "!Base64",
    "!Ref",
    "!Sub"
  ],
  "editor.formatOnSave": true,
  "editor.rulers": [80, 120],
  "[yaml]": {
    "editor.insertSpaces": true,
    "editor.tabSize": 2
  }
}
```

## 開発ワークフロー

### 1. 新機能開発

```bash
# 1. Feature branch作成
git checkout -b feature/new-app

# 2. アプリケーションマニフェスト作成
mkdir -p manifests/apps/new-app
cat > manifests/apps/new-app/deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: new-app
  namespace: sandbox
spec:
  replicas: 2
  selector:
    matchLabels:
      app: new-app
  template:
    metadata:
      labels:
        app: new-app
    spec:
      containers:
      - name: app
        image: nginx:latest
        ports:
        - containerPort: 80
EOF

# 3. ローカルテスト
kubectl apply -f manifests/apps/new-app/ --dry-run=client
kubectl apply -f manifests/apps/new-app/

# 4. 動作確認
kubectl get pods -n sandbox
kubectl port-forward -n sandbox deployment/new-app 8080:80

# 5. コミット
git add manifests/apps/new-app/
git commit -m "feat: Add new-app deployment"
```

### 2. ArgoCD Application作成

```yaml
# manifests/resources/applications/new-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: new-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/ksera524/k8s_myHome
    targetRevision: HEAD
    path: manifests/apps/new-app
  destination:
    server: https://kubernetes.default.svc
    namespace: sandbox
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

### 3. CI/CDパイプライン設定

```yaml
# .github/workflows/new-app.yml
name: New App CI/CD

on:
  push:
    branches: [main]
    paths:
      - 'apps/new-app/**'
      - '.github/workflows/new-app.yml'
  pull_request:
    branches: [main]
    paths:
      - 'apps/new-app/**'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    
    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3
    
    - name: Build and test
      run: |
        docker build -t new-app:test apps/new-app/
        docker run --rm new-app:test npm test
    
    - name: Push to Harbor
      if: github.ref == 'refs/heads/main'
      run: |
        echo ${{ secrets.HARBOR_PASSWORD }} | docker login harbor.local -u admin --password-stdin
        docker tag new-app:test harbor.local/apps/new-app:${{ github.sha }}
        docker push harbor.local/apps/new-app:${{ github.sha }}
    
    - name: Update manifest
      if: github.ref == 'refs/heads/main'
      run: |
        sed -i "s|image: .*|image: harbor.local/apps/new-app:${{ github.sha }}|" manifests/apps/new-app/deployment.yaml
        git config user.name github-actions
        git config user.email github-actions@github.com
        git add manifests/apps/new-app/deployment.yaml
        git commit -m "chore: Update new-app image to ${{ github.sha }}"
        git push
```

## ローカルテスト

### 1. Unit Test
```bash
# Go アプリケーション
go test ./...

# Rust アプリケーション
cargo test

# Python アプリケーション
pytest tests/

# Node.js アプリケーション
npm test
```

### 2. Integration Test
```bash
# Kubernetes マニフェスト検証
kubectl apply -f manifests/ --dry-run=server

# Helm Chart検証
helm lint charts/my-chart
helm template charts/my-chart

# ArgoCD検証
argocd app create test-app \
  --repo https://github.com/ksera524/k8s_myHome \
  --path manifests/apps/new-app \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace sandbox \
  --dry-run
```

### 3. E2E Test
```bash
#!/bin/bash
# e2e-test.sh

# デプロイ
kubectl apply -f manifests/apps/new-app/

# ヘルスチェック待機
kubectl wait --for=condition=available \
  --timeout=300s \
  deployment/new-app -n sandbox

# テスト実行
APP_URL=$(kubectl get svc new-app -n sandbox -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -f http://${APP_URL}/health || exit 1

# クリーンアップ
kubectl delete -f manifests/apps/new-app/
```

## デバッグ手法

### 1. Pod デバッグ
```bash
# ログ確認
kubectl logs -n sandbox deployment/new-app --follow

# Pod内でコマンド実行
kubectl exec -n sandbox -it deployment/new-app -- bash

# デバッグコンテナ起動
kubectl debug -n sandbox deployment/new-app -it --image=busybox

# イベント確認
kubectl get events -n sandbox --sort-by='.lastTimestamp'
```

### 2. ネットワークデバッグ
```bash
# Service確認
kubectl get svc -n sandbox
kubectl describe svc new-app -n sandbox

# Endpoints確認
kubectl get endpoints -n sandbox

# DNS確認
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup new-app.sandbox.svc.cluster.local

# ネットワークポリシー確認
kubectl get networkpolicies -n sandbox
```

### 3. リソースデバッグ
```bash
# リソース使用状況
kubectl top pods -n sandbox
kubectl top nodes

# リソース制限確認
kubectl describe pod -n sandbox | grep -A 5 Limits

# PVC確認
kubectl get pvc -n sandbox
kubectl describe pvc -n sandbox
```

## パフォーマンスチューニング

### 1. アプリケーション最適化
```yaml
# HPA設定
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: new-app-hpa
  namespace: sandbox
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: new-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 80
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

### 2. イメージ最適化
```dockerfile
# マルチステージビルド
FROM golang:1.21 AS builder
WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 go build -o app

FROM scratch
COPY --from=builder /app/app /app
ENTRYPOINT ["/app"]
```

## セキュリティベストプラクティス

### 1. SecurityContext設定
```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 2000
      containers:
      - name: app
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
```

### 2. NetworkPolicy設定
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: new-app-netpol
  namespace: sandbox
spec:
  podSelector:
    matchLabels:
      app: new-app
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - port: 80
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: harbor
  - to:
    - podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - port: 53
      protocol: UDP
```

## トラブルシューティング

### よくある問題と解決方法

#### ImagePullBackOff
```bash
# Secret確認
kubectl get secret -n sandbox
kubectl create secret docker-registry regcred \
  --docker-server=harbor.local \
  --docker-username=admin \
  --docker-password=password \
  -n sandbox
```

#### CrashLoopBackOff
```bash
# ログ確認
kubectl logs -n sandbox pod-name --previous
# リソース制限確認
kubectl describe pod -n sandbox pod-name | grep -A 10 "Containers:"
```

#### Pending Pod
```bash
# ノードリソース確認
kubectl describe nodes
kubectl get pods -o wide
# PVC確認
kubectl get pvc -n sandbox
```

---
*最終更新: 2025-01-09*