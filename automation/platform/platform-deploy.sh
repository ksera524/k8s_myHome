#!/bin/bash

# Kubernetes基盤構築スクリプト - ArgoCD→ESO従来順序版
# MetalLB + Ingress Controller + cert-manager + ArgoCD → ESO → Harbor

set -euo pipefail

# 非対話モード設定
export DEBIAN_FRONTEND=noninteractive
export NON_INTERACTIVE=true

# GitHub認証情報管理ユーティリティを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/argocd/github-auth-utils.sh"

# 共通色設定スクリプトを読み込み（settings-loader.shより先に）
source "$SCRIPT_DIR/../scripts/common-colors.sh"

# 設定ファイル読み込み（環境変数が未設定の場合）
if [[ -f "$SCRIPT_DIR/../scripts/settings-loader.sh" ]]; then
    print_debug "settings.tomlから設定を読み込み中..."
    source "$SCRIPT_DIR/../scripts/settings-loader.sh" load 2>/dev/null || true
    
    # settings.tomlからのPULUMI_ACCESS_TOKEN設定を確認・適用
    if [[ -n "${PULUMI_ACCESS_TOKEN:-}" ]]; then
        print_debug "settings.tomlからPulumi Access Token読み込み完了"
    elif [[ -n "${PULUMI_PULUMI_ACCESS_TOKEN:-}" ]]; then
        export PULUMI_ACCESS_TOKEN="${PULUMI_PULUMI_ACCESS_TOKEN}"
        print_debug "settings.tomlのPulumi.access_tokenを環境変数に設定完了"
    fi
fi

print_status "=== Kubernetes基盤構築開始 ==="

# 0. マニフェストファイルの準備
print_status "マニフェストファイルをリモートにコピー中..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scp -o StrictHostKeyChecking=no "../../manifests/infrastructure/networking/metallb/metallb-ipaddress-pool.yaml" k8suser@192.168.122.10:/tmp/
scp -o StrictHostKeyChecking=no "../../manifests/infrastructure/security/cert-manager/cert-manager-selfsigned-issuer.yaml" k8suser@192.168.122.10:/tmp/
scp -o StrictHostKeyChecking=no "../../manifests/core/storage-classes/local-storage-class.yaml" k8suser@192.168.122.10:/tmp/
scp -o StrictHostKeyChecking=no "$SCRIPT_DIR/../templates/platform/argocd-ingress.yaml" k8suser@192.168.122.10:/tmp/
scp -o StrictHostKeyChecking=no "../../manifests/infrastructure/gitops/argocd/argocd-config.yaml" k8suser@192.168.122.10:/tmp/
# ArgoCD OAuth Secret は GitOps 経由で管理されるため、コピー不要
# scp -o StrictHostKeyChecking=no "../../manifests/platform/secrets/external-secrets/argocd-github-oauth-secret.yaml" k8suser@192.168.122.10:/tmp/
scp -o StrictHostKeyChecking=no "../../manifests/bootstrap/app-of-apps.yaml" k8suser@192.168.122.10:/tmp/
print_status "✓ マニフェストファイルコピー完了"

# 1. 前提条件確認
print_status "前提条件を確認中..."

# SSH known_hosts クリーンアップ
print_debug "SSH known_hosts をクリーンアップ中..."
ssh-keygen -f "$HOME/.ssh/known_hosts" -R '192.168.122.10' 2>/dev/null || true
ssh-keygen -f "$HOME/.ssh/known_hosts" -R '192.168.122.11' 2>/dev/null || true  
ssh-keygen -f "$HOME/.ssh/known_hosts" -R '192.168.122.12' 2>/dev/null || true

# k8sクラスタ接続確認
print_debug "k8sクラスタ接続を確認中..."
if ! ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=10 k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
    print_error "k8sクラスタに接続できません"
    print_error "Phase 3のk8sクラスタ構築を先に完了してください"
    print_error "注意: このスクリプトはUbuntuホストマシンで実行してください（WSL2不可）"
    exit 1
fi

READY_NODES=$(ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 'kubectl get nodes --no-headers' | grep -c Ready || echo "0")
if [[ $READY_NODES -lt 2 ]]; then
    print_error "Ready状態のNodeが2台未満です（現在: $READY_NODES台）"
    exit 1
else
    print_status "✓ k8sクラスタ（$READY_NODES Node）接続OK"
fi

# Phase 4.1: MetalLB インストール
print_status "=== Phase 4.1: MetalLB インストール ==="
print_debug "LoadBalancer機能を提供します"

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
# MetalLB namespace作成
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

# MetalLB起動まで待機
echo "MetalLB Pod起動を待機中..."
kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=300s

# IPアドレスプール設定（libvirtデフォルトネットワーク範囲）
kubectl apply -f /tmp/metallb-ipaddress-pool.yaml

echo "✓ MetalLB設定完了"
EOF

print_status "✓ MetalLB インストール完了"

# Phase 4.2: Ingress Controller (NGINX) インストール
print_status "=== Phase 4.2: NGINX Ingress Controller インストール ==="
print_debug "HTTP/HTTPSルーティング機能を提供します"

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
# NGINX Ingress Controller インストール
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml

# Ingress Controller起動まで待機
echo "NGINX Ingress Controller起動を待機中..."
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s

# LoadBalancer ServiceのIP確認
echo "LoadBalancer IP確認中..."
kubectl -n ingress-nginx get service ingress-nginx-controller

echo "✓ NGINX Ingress Controller設定完了"
EOF

print_status "✓ NGINX Ingress Controller インストール完了"

# Phase 4.3: cert-manager インストール
print_status "=== Phase 4.3: cert-manager インストール ==="
print_debug "TLS証明書自動管理機能を提供します"

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
# cert-manager インストール
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# cert-manager起動まで待機
echo "cert-manager起動を待機中..."
kubectl wait --namespace cert-manager --for=condition=ready pod --selector=app.kubernetes.io/instance=cert-manager --timeout=300s

# Self-signed ClusterIssuer作成（開発用）
kubectl apply -f /tmp/cert-manager-selfsigned-issuer.yaml

echo "✓ cert-manager設定完了"
EOF

print_status "✓ cert-manager インストール完了"

# Phase 4.4: StorageClass設定
print_status "=== Phase 4.4: StorageClass設定 ==="
print_debug "永続ストレージ機能を設定します"

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
# Local StorageClass作成
kubectl apply -f /tmp/local-storage-class.yaml

echo "✓ StorageClass設定完了"
EOF

print_status "✓ StorageClass設定完了"

# Phase 4.5: 必要namespace作成
print_status "=== Phase 4.5: 必要namespace作成 ==="
print_debug "各コンポーネント用のnamespaceを事前作成します"

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
# ArgoCD namespace作成（ArgoCD自体に必要）
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "✓ ArgoCD namespace作成完了"
EOF

print_status "✓ ArgoCD namespace作成完了"

# Phase 4.6: ArgoCD デプロイ
print_status "=== Phase 4.6: ArgoCD デプロイ ==="
print_debug "GitOps基盤をセットアップします"

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
# ArgoCD インストール
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# ArgoCD起動まで待機
echo "ArgoCD起動を待機中..."
kubectl wait --namespace argocd --for=condition=ready pod --selector=app.kubernetes.io/component=server --timeout=300s

# ArgoCD insecureモード設定（HTTPアクセス対応）
echo "ArgoCD insecureモード設定中..."
kubectl patch configmap argocd-cmd-params-cm -n argocd -p '{"data":{"server.insecure":"true"}}'

# ArgoCD管理者パスワード取得・表示
echo "ArgoCD管理者パスワード:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""

# ArgoCD Ingress設定（HTTP対応）
kubectl apply -f /tmp/argocd-ingress.yaml

echo "✓ ArgoCD基本設定完了"
EOF

print_status "✓ ArgoCD デプロイ完了"

# Phase 4.7: ESO デプロイ (ArgoCD Application経由)
print_status "=== Phase 4.7: External Secrets Operator デプロイ ==="
print_debug "Secret管理統合機能をArgoCD経由でデプロイします"

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
# ESO Application作成（ArgoCD経由）
kubectl apply -f - <<EOYAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-secrets-operator
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://charts.external-secrets.io'
    targetRevision: '0.18.2'
    chart: external-secrets
    helm:
      values: |
        installCRDs: true
        replicaCount: 1
        resources:
          limits:
            cpu: 100m
            memory: 128Mi
          requests:
            cpu: 10m
            memory: 32Mi
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: external-secrets-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - Replace=true
EOYAML

echo "ESO Application作成完了、同期待機中..."
sleep 30

# ESO同期確認
kubectl wait --for=condition=Synced --timeout=300s application/external-secrets-operator -n argocd
kubectl wait --namespace external-secrets-system --for=condition=ready pod --selector=app.kubernetes.io/name=external-secrets --timeout=300s

echo "✓ External Secrets Operator デプロイ完了"

# App-of-Appsパターン適用（ESO作成後すぐに）
echo "App-of-Apps適用中..."
kubectl apply -f /tmp/app-of-apps.yaml

# 基本Application（infrastructure, platform）の同期待機
echo "基本Application同期待機中..."
sleep 20

# Infrastructure Application同期確認
if kubectl get application infrastructure -n argocd 2>/dev/null; then
    kubectl wait --for=condition=Synced --timeout=300s application/infrastructure -n argocd || echo "Infrastructure同期継続中"
fi

# Platform Application同期確認
if kubectl get application platform -n argocd 2>/dev/null; then
    kubectl wait --for=condition=Synced --timeout=300s application/platform -n argocd || echo "Platform同期継続中"
fi

echo "✓ App-of-Apps適用完了"
EOF

print_status "✓ External Secrets Operator デプロイ完了"

# Phase 4.8: ArgoCD GitHub OAuth設定 (ESO経由)
print_status "=== Phase 4.8: ArgoCD GitHub OAuth設定 ==="
print_debug "GitHub OAuth設定をExternal Secrets経由で行います"

# PULUMI_ACCESS_TOKEN確認
if [ -z "${PULUMI_ACCESS_TOKEN:-}" ]; then
    print_warning "PULUMI_ACCESS_TOKEN未設定、手動Secret作成にフォールバック"
    
    # GitHub Client Secretのフォールバック作成
    ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
# フォールバック: 手動でGitHub OAuth Secret作成
echo "GitHub OAuth Secret手動作成中..."
kubectl patch secret argocd-secret -n argocd -p '{"data":{"dex.github.clientSecret":"Z2hwX0ROUlVKVGxKNVVFeEtZTXIzODIzNnJ5Y1Uwd1A4VDI3ZGJmYw=="}}'

# ArgoCD GitHub OAuth ConfigMap適用
kubectl apply -f /tmp/argocd-config.yaml

# ArgoCD サーバー再起動
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd --timeout=300s

echo "✓ ArgoCD GitHub OAuth手動設定完了"
EOF
else
    print_debug "Pulumi Access Token設定済み、ESO経由でSecret管理します"
    
    ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << EOF
# Pulumi Access Token Secret作成
kubectl create secret generic pulumi-esc-token \
  --namespace external-secrets-system \
  --from-literal=accessToken="${PULUMI_ACCESS_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Platform Application存在確認
if kubectl get application platform -n argocd 2>/dev/null; then
    # Platform Application同期を手動トリガー（ESOリソース適用のため）
    echo "Platform Application同期をトリガー中..."
    kubectl patch application platform -n argocd --type merge -p '{"operation": {"sync": {"syncStrategy": {"hook": {}}}}}'
    
    # Platform同期待機（ESO関連リソースが作成される）
    echo "Platform同期待機中（ESOリソース作成）..."
    kubectl wait --for=condition=Synced --timeout=300s application/platform -n argocd || echo "Platform同期継続中"
else
    echo "Platform Application未作成、App-of-Apps適用確認中..."
    # App-of-Appsが適用されているか確認
    if ! kubectl get application app-of-apps -n argocd 2>/dev/null; then
        echo "App-of-Apps再適用中..."
        kubectl apply -f /tmp/app-of-apps.yaml
        sleep 20
    fi
    
    # Platform Application作成待機
    timeout=60
    while [ \$timeout -gt 0 ]; do
        if kubectl get application platform -n argocd 2>/dev/null; then
            echo "✓ Platform Application作成確認"
            # 同期トリガー
            kubectl patch application platform -n argocd --type merge -p '{"operation": {"sync": {"syncStrategy": {"hook": {}}}}}'
            break
        fi
        echo "Platform Application作成待機中... (残り \${timeout}秒)"
        sleep 5
        timeout=\$((timeout - 5))
    done
fi

# ClusterSecretStore準備完了待機
echo "ClusterSecretStore準備完了待機中..."
timeout=60
while [ \$timeout -gt 0 ]; do
    if kubectl get clustersecretstore pulumi-esc-store 2>/dev/null | grep -q Ready; then
        echo "✓ ClusterSecretStore準備完了"
        break
    fi
    echo "ClusterSecretStore待機中... (残り \${timeout}秒)"
    sleep 5
    timeout=\$((timeout - 5))
done

if [ \$timeout -le 0 ]; then
    echo "⚠️ ClusterSecretStore作成タイムアウト、手動Secret作成にフォールバック"
    kubectl patch secret argocd-secret -n argocd -p '{"data":{"dex.github.clientSecret":"Z2hwX0ROUlVKVGxKNVVFeEtZTXIzODIzNnJ5Y1Uwd1A4VDI3ZGJmYw=="}}'
else
    # External Secret同期待機（ArgoCD GitHub OAuth）
    timeout=60
    while [ \$timeout -gt 0 ]; do
        if kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.dex\.github\.clientSecret}' 2>/dev/null | grep -q .; then
            SECRET_LENGTH=\$(kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.dex\.github\.clientSecret}' | base64 -d | wc -c)
            if [ "\$SECRET_LENGTH" -gt 10 ]; then
                echo "✓ ArgoCD GitHub OAuth ESO同期完了"
                break
            fi
        fi
        echo "External Secret同期待機中... (残り \${timeout}秒)"
        sleep 5
        timeout=\$((timeout - 5))
    done
    
    if [ \$timeout -le 0 ]; then
        echo "⚠️ ESO同期タイムアウト、手動Secret作成にフォールバック"
        kubectl patch secret argocd-secret -n argocd -p '{"data":{"dex.github.clientSecret":"Z2hwX0ROUlVKVGxKNVVFeEtZTXIzODIzNnJ5Y1Uwd1A4VDI3ZGJmYw=="}}'
    fi
fi

# ArgoCD GitHub OAuth ConfigMap適用
kubectl apply -f /tmp/argocd-config.yaml

# ArgoCD サーバー再起動
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd --timeout=300s

echo "✓ ArgoCD GitHub OAuth設定完了"
EOF
fi

print_status "✓ ArgoCD GitHub OAuth設定完了"

# Phase 4.9: Harbor デプロイ
print_status "=== Phase 4.9: Harbor デプロイ ==="
print_debug "Harbor Private Registry をArgoCD経由でデプロイします"

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
# Infrastructure Application確認（App-of-Appsは既に適用済み）
if kubectl get application infrastructure -n argocd 2>/dev/null; then
    echo "Infrastructure Application確認済み"
    # Harbor Application同期確認
    kubectl wait --for=condition=Synced --timeout=300s application/infrastructure -n argocd || echo "Harbor同期継続中"
else
    echo "Infrastructure Application未作成、App-of-Apps再確認中..."
    kubectl get application -n argocd
fi

echo "✓ Harbor デプロイ完了"
EOF

print_status "✓ Harbor デプロイ完了"

# Phase 4.9.5: Harbor認証設定（skopeo対応）
print_status "=== Phase 4.9.5: Harbor認証設定（skopeo対応） ==="
print_debug "Harbor認証情報secretをGitHub Actions用に設定します"

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
# Harbor管理者パスワード取得 (ESO経由)
HARBOR_ADMIN_PASSWORD=$(kubectl get secret harbor-admin-secret -n harbor -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
if [[ -z "$HARBOR_ADMIN_PASSWORD" ]]; then
    echo "エラー: Harbor管理者パスワードをESOから取得できませんでした"
    exit 1
fi

# arc-systems namespace に harbor-auth secret 作成
kubectl create secret generic harbor-auth \
    --namespace arc-systems \
    --from-literal=HARBOR_USERNAME="admin" \
    --from-literal=HARBOR_PASSWORD="$HARBOR_ADMIN_PASSWORD" \
    --from-literal=HARBOR_URL="192.168.122.100" \
    --from-literal=HARBOR_PROJECT="sandbox" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Harbor認証Secret (arc-systems) 作成完了"

# 必要なネームスペースにHarbor Docker registry secret作成
NAMESPACES=("default" "sandbox" "production" "staging")

for namespace in "${NAMESPACES[@]}"; do
    # ネームスペース作成（存在しない場合）
    kubectl create namespace $namespace --dry-run=client -o yaml | kubectl apply -f -
    
    # harbor-http Docker registry secret作成
    kubectl create secret docker-registry harbor-http \
        --namespace $namespace \
        --docker-server="192.168.122.100" \
        --docker-username="admin" \
        --docker-password="$HARBOR_ADMIN_PASSWORD" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    echo "✓ harbor-http secret ($namespace) 作成完了"
done

echo "✓ Harbor認証設定完了 - skopeo対応"
EOF

print_status "✓ Harbor認証設定（skopeo対応）完了"

# Phase 4.9.6: Worker ノード Containerd Harbor HTTP Registry設定
print_status "=== Phase 4.9.6: Containerd Harbor HTTP Registry設定 ==="
print_debug "各Worker ノードのContainerdにHarbor HTTP Registry設定を追加します"

# Harbor admin パスワード取得（ローカルで実行）
HARBOR_ADMIN_PASSWORD=$(ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 'kubectl get secret harbor-admin-secret -n harbor -o jsonpath="{.data.password}" 2>/dev/null | base64 -d')
if [[ -z "$HARBOR_ADMIN_PASSWORD" ]]; then
    print_error "エラー: Harbor管理者パスワードをESOから取得できませんでした"
    exit 1
fi

print_debug "Worker1 (192.168.122.11) Containerd設定..."
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.11 << EOF
# Containerd設定バックアップ
sudo -n cp /etc/containerd/config.toml /etc/containerd/config.toml.backup-\$(date +%Y%m%d-%H%M%S)

# Harbor Registry設定追加（HTTP + 認証）
sudo -n tee -a /etc/containerd/config.toml > /dev/null << 'CONTAINERD_EOF'

[plugins."io.containerd.grpc.v1.cri".registry.mirrors."192.168.122.100"]
  endpoint = ["http://192.168.122.100"]

[plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.122.100".tls]
  insecure_skip_verify = true

[plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.122.100".auth]
  username = "admin"
  password = "${HARBOR_ADMIN_PASSWORD}"
CONTAINERD_EOF

# Containerd再起動
sudo -n systemctl restart containerd
echo "✓ Worker1 Containerd設定完了"
EOF

print_debug "Worker2 (192.168.122.12) Containerd設定..."
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.12 << EOF
# Containerd設定バックアップ
sudo -n cp /etc/containerd/config.toml /etc/containerd/config.toml.backup-\$(date +%Y%m%d-%H%M%S)

# Harbor Registry設定追加（HTTP + 認証）
sudo -n tee -a /etc/containerd/config.toml > /dev/null << 'CONTAINERD_EOF'

[plugins."io.containerd.grpc.v1.cri".registry.mirrors."192.168.122.100"]
  endpoint = ["http://192.168.122.100"]

[plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.122.100".tls]
  insecure_skip_verify = true

[plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.122.100".auth]
  username = "admin"
  password = "${HARBOR_ADMIN_PASSWORD}"
CONTAINERD_EOF

# Containerd再起動
sudo -n systemctl restart containerd
echo "✓ Worker2 Containerd設定完了"
EOF

print_status "✓ Containerd Harbor HTTP Registry設定完了"

# Phase 4.10: GitHub Actions Runner Controller (ARC) セットアップ
print_status "=== Phase 4.10: GitHub Actions Runner Controller セットアップ ==="
print_debug "GitHub Actions Runner Controller を直接セットアップします"

# ARCセットアップスクリプト実行
if [[ -f "$SCRIPT_DIR/../scripts/github-actions/setup-arc.sh" ]]; then
    print_debug "ARC セットアップスクリプトを実行中..."
    export NON_INTERACTIVE=true
    bash "$SCRIPT_DIR/../scripts/github-actions/setup-arc.sh"
    print_status "✓ ARC セットアップ完了"
else
    print_warning "setup-arc.sh が見つかりません。ArgoCD経由でのデプロイにフォールバック"
    ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
    # Platform Application同期確認
    kubectl wait --for=condition=Synced --timeout=300s application/platform -n argocd || echo "ARC同期継続中"
    echo "✓ ARC デプロイ完了"
EOF
fi

# Phase 4.10.5: settings.tomlのリポジトリを自動add-runner
print_status "=== Phase 4.10.5: settings.tomlのリポジトリを自動add-runner ==="
print_debug "settings.tomlからリポジトリリストを読み込み中..."

SETTINGS_FILE="$SCRIPT_DIR/../settings.toml"
if [[ -f "$SETTINGS_FILE" ]]; then
    # arc_repositoriesセクションを解析
    ARC_REPOS_TEMP=$(sed -n '/^arc_repositories = \[/,/^]/p' "$SETTINGS_FILE" | grep -E '^\s*\[".*"\s*,.*\]')
    
    if [[ -n "$ARC_REPOS_TEMP" ]]; then
        print_debug "arc_repositories設定を発見しました"
        
        # 各リポジトリに対してadd-runner.shを実行
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            
            # 正規表現で配列要素を抽出: ["name", min, max, "description"]
            if [[ $line =~ \[\"([^\"]+)\",\ *([0-9]+),\ *([0-9]+), ]]; then
                REPO_NAME="${BASH_REMATCH[1]}"
                
                print_status "🏃 $REPO_NAME のRunnerを追加中..."
                
                # add-runner.shを実行
                if [[ -f "$SCRIPT_DIR/../scripts/github-actions/add-runner.sh" ]]; then
                    bash "$SCRIPT_DIR/../scripts/github-actions/add-runner.sh" "$REPO_NAME"
                    print_status "✓ $REPO_NAME Runner追加完了"
                else
                    print_error "add-runner.sh が見つかりません"
                fi
            fi
        done <<< "$ARC_REPOS_TEMP"
        
        print_status "✓ settings.tomlのリポジトリ自動追加完了"
    else
        print_debug "arc_repositories設定が見つかりません（スキップ）"
    fi
else
    print_warning "settings.tomlが見つかりません"
fi

# Phase 4.11: 各種Application デプロイ
print_status "=== Phase 4.11: 各種Application デプロイ ==="
print_debug "Cloudflared等のApplicationをArgoCD経由でデプロイします"

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
# ESOリソースが適用されているか確認
echo "External Secrets リソース確認中..."
if kubectl get clustersecretstore pulumi-esc-store 2>/dev/null | grep -q Ready; then
    echo "✓ ClusterSecretStore確認OK"
else
    echo "⚠️ ClusterSecretStore未検出、Platform同期を再実行..."
    # Platform Application存在確認
    if kubectl get application platform -n argocd 2>/dev/null; then
        kubectl patch application platform -n argocd --type merge -p '{"operation": {"sync": {"syncStrategy": {"hook": {}}}}}'
        sleep 30
    else
        echo "Platform Application未作成、スキップ"
    fi
fi

# Applications同期確認
kubectl wait --for=condition=Synced --timeout=300s application/applications -n argocd || echo "Applications同期継続中"

# アプリケーション用External Secrets確認
echo "アプリケーション用External Secrets確認中..."
kubectl get externalsecrets -A | grep -E "(cloudflared|slack)" || echo "アプリケーションExternal Secrets待機中"

echo "✓ 各種Application デプロイ完了"
EOF

print_status "✓ 各種Application デプロイ完了"


# Phase 4.12: システム環境確認
print_status "=== Phase 4.12: システム環境確認 ==="
print_debug "デプロイされたシステム全体の動作確認を行います"

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
echo "=== 最終システム状態確認 ==="

# ArgoCD状態確認
echo "ArgoCD状態:"
kubectl get pods -n argocd -l app.kubernetes.io/component=server

# External Secrets状態確認
echo "External Secrets状態:"
kubectl get pods -n external-secrets-system -l app.kubernetes.io/name=external-secrets

# ClusterSecretStore状態確認
echo "ClusterSecretStore状態:"
kubectl get clustersecretstore pulumi-esc-store 2>/dev/null || echo "ClusterSecretStore未作成"

# ExternalSecrets状態確認
echo "ExternalSecrets状態:"
kubectl get externalsecrets -A --no-headers | awk '{print "  - " $2 " (" $1 "): " $(NF)}' 2>/dev/null || echo "ExternalSecrets未作成"

# Harbor状態確認
echo "Harbor状態:"
kubectl get pods -n harbor -l app=harbor 2>/dev/null || echo "Harbor デプロイ中..."

# ARC状態確認
echo "GitHub Actions Runner Controller状態:"
kubectl get pods -n arc-systems -l app.kubernetes.io/component=controller 2>/dev/null || echo "ARC デプロイ中..."

# Cloudflared状態確認
echo "Cloudflared状態:"
kubectl get pods -n cloudflared 2>/dev/null || echo "Cloudflared デプロイ中..."

# LoadBalancer IP確認
echo "LoadBalancer IP:"
kubectl -n ingress-nginx get service ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
echo ""

# ArgoCD Applications状態
echo "ArgoCD Applications状態:"
kubectl get applications -n argocd --no-headers | awk '{print "  - " $1 " (" $2 "/" $3 ")"}'

echo "✓ システム環境確認完了"
EOF

print_status "✓ システム環境確認完了"

print_status "=== Kubernetesプラットフォーム構築完了（skopeo対応） ==="
print_status "アクセス方法:"
print_status "  ArgoCD UI: https://argocd.qroksera.com"
print_status "  Harbor UI: https://harbor.qroksera.com"
print_status "  LoadBalancer IP: 192.168.122.100"
print_status ""
print_status "Harbor push設定:"
print_status "  - GitHub ActionsでskopeoによるTLS検証無効push対応"
print_status "  - Harbor認証secret (arc-systems/harbor-auth) 設定済み"
print_status "  - イメージプルsecret (各namespace/harbor-http) 設定済み"

# Harbor IP Ingress を作成
print_status "Harbor IP Ingress を作成中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
# Harbor IP Ingress が存在しない場合のみ作成
if ! kubectl get ingress -n harbor harbor-ip-ingress >/dev/null 2>&1; then
    echo "Harbor IP Ingress を作成中..."
    kubectl apply -f - << 'INGRESS_EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: harbor-ip-ingress
  namespace: harbor
  labels:
    app: harbor
    chart: harbor
    heritage: Helm
    release: harbor
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /api/
        pathType: Prefix
        backend:
          service:
            name: harbor-core
            port:
              number: 80
      - path: /service/
        pathType: Prefix
        backend:
          service:
            name: harbor-core
            port:
              number: 80
      - path: /v2/
        pathType: Prefix
        backend:
          service:
            name: harbor-core
            port:
              number: 80
      - path: /chartrepo/
        pathType: Prefix
        backend:
          service:
            name: harbor-core
            port:
              number: 80
      - path: /c/
        pathType: Prefix
        backend:
          service:
            name: harbor-core
            port:
              number: 80
      - path: /
        pathType: Prefix
        backend:
          service:
            name: harbor-portal
            port:
              number: 80
INGRESS_EOF
    echo "✓ Harbor IP Ingress 作成完了"
else
    echo "✓ Harbor IP Ingress は既に存在します"
fi
EOF
print_status "✓ Harbor IP Ingress 設定完了"

# Harbor の動作確認
print_status "Harbor の動作確認中..."
if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'curl -s -f http://192.168.122.100/api/v2.0/systeminfo' >/dev/null 2>&1; then
    print_status "✓ Harbor API が正常に応答しています"
else
    print_warning "Harbor API の応答確認に失敗しました（Harbor は起動中の可能性があります）"
fi

print_status "🎉 すべての設定が完了しました！"
print_status ""
print_status "次のステップ:"
print_status "  1. GitHub リポジトリに workflow ファイルを追加"
print_status "  2. make add-runner REPO=your-repo でリポジトリ用の Runner を追加"
print_status "  3. git push で GitHub Actions が自動実行されます"