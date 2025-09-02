#!/bin/bash

# Kubernetes基盤構築スクリプト - GitOps管理版
# ArgoCD → App-of-Apps (MetalLB, Ingress, cert-manager, ESO等を統合管理) → Harbor

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
scp -o StrictHostKeyChecking=no "../../manifests/core/storage-classes/local-storage-class.yaml" k8suser@192.168.122.10:/tmp/
scp -o StrictHostKeyChecking=no "$SCRIPT_DIR/../templates/platform/argocd-ingress.yaml" k8suser@192.168.122.10:/tmp/
# ArgoCD ConfigMapはGitOps経由で管理されるため、コピー不要
# scp -o StrictHostKeyChecking=no "../../manifests/infrastructure/gitops/argocd/argocd-config.yaml" k8suser@192.168.122.10:/tmp/
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

# Phase 4.1-4.3: 基盤インフラ（MetalLB, NGINX Ingress, cert-manager）はGitOps管理へ移行
print_status "=== Phase 4.1-4.3: 基盤インフラはGitOps管理 ==="
print_debug "MetalLB, NGINX Ingress, cert-managerはArgoCD経由でデプロイされます"



# Phase 4.4: StorageClass設定
print_status "=== Phase 4.4: StorageClass設定 ==="
print_debug "永続ストレージ機能を設定します"

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
# Local StorageClass作成
kubectl apply -f /tmp/local-storage-class.yaml

echo "✓ StorageClass設定完了"
EOF

print_status "✓ StorageClass設定完了"

# Phase 4.5: ArgoCD デプロイ
print_status "=== Phase 4.5: ArgoCD デプロイ ==="
print_debug "GitOps基盤をセットアップします"

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
# ArgoCD namespace作成（ArgoCD自体に必要）
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

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

# Phase 4.6: App-of-Apps デプロイ
print_status "=== Phase 4.6: App-of-Apps パターン適用 ==="
print_debug "すべてのApplicationをGitOps管理でデプロイします"

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << EOF
# App-of-Appsパターン適用（すべてのApplicationを管理）
echo "App-of-Apps適用中..."
kubectl apply -f /tmp/app-of-apps.yaml

# 基盤インフラApplication同期待機
echo "基盤インフラApplication同期待機中..."
sleep 30

# MetalLB同期確認
if kubectl get application metallb -n argocd 2>/dev/null; then
    echo "MetalLB同期待機中..."
    kubectl wait --for=condition=Synced --timeout=300s application/metallb -n argocd || echo "MetalLB同期継続中"
    kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=300s || echo "MetalLB Pod起動待機中"
fi

# NGINX Ingress同期確認
if kubectl get application ingress-nginx -n argocd 2>/dev/null; then
    echo "NGINX Ingress同期待機中..."
    kubectl wait --for=condition=Synced --timeout=300s application/ingress-nginx -n argocd || echo "NGINX Ingress同期継続中"
    kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s || echo "NGINX Ingress Pod起動待機中"
fi

# cert-manager同期確認
if kubectl get application cert-manager -n argocd 2>/dev/null; then
    echo "cert-manager同期待機中..."
    kubectl wait --for=condition=Synced --timeout=300s application/cert-manager -n argocd || echo "cert-manager同期継続中"
    kubectl wait --namespace cert-manager --for=condition=ready pod --selector=app.kubernetes.io/instance=cert-manager --timeout=300s || echo "cert-manager Pod起動待機中"
fi

# ESO同期確認
if kubectl get application external-secrets-operator -n argocd 2>/dev/null; then
    echo "External Secrets Operator同期待機中..."
    kubectl wait --for=condition=Synced --timeout=300s application/external-secrets-operator -n argocd || echo "ESO同期継続中"
    kubectl wait --namespace external-secrets-system --for=condition=ready pod --selector=app.kubernetes.io/name=external-secrets --timeout=300s || echo "ESO Pod起動待機中"
    
    # Pulumi Access Token Secret作成（ESO起動後すぐに）
    if [[ -n "${PULUMI_ACCESS_TOKEN}" ]]; then
        echo "Pulumi Access Token Secret作成中..."
        kubectl create secret generic pulumi-esc-token \\
          --namespace external-secrets-system \\
          --from-literal=accessToken="${PULUMI_ACCESS_TOKEN}" \\
          --dry-run=client -o yaml | kubectl apply -f -
        echo "✓ Pulumi Access Token Secret作成完了"
    else
        echo "エラー: PULUMI_ACCESS_TOKEN が設定されていません"
        echo "External Secrets Operator が正常に動作しません"
        echo "settings.toml に Pulumi Access Token を設定してください"
        exit 1
    fi
fi

# Platform Application同期確認
if kubectl get application platform -n argocd 2>/dev/null; then
    kubectl wait --for=condition=Synced --timeout=300s application/platform -n argocd || echo "Platform同期継続中"
fi

echo "✓ App-of-Apps適用完了"
EOF

print_status "✓ App-of-Apps デプロイ完了"

# Phase 4.7: ArgoCD GitHub OAuth設定 (ESO経由)
print_status "=== Phase 4.7: ArgoCD GitHub OAuth設定 ==="
print_debug "GitHub OAuth設定をExternal Secrets経由で行います"

# Pulumi Access TokenがEOFブロック内で既に作成されているか確認
ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
# Pulumi Access Token Secretの存在確認
if kubectl get secret pulumi-esc-token -n external-secrets-system 2>/dev/null; then
    echo "✓ Pulumi Access Token Secret確認済み"
else
    echo "エラー: Pulumi Access Token Secret が見つかりません"
    echo "External Secrets Operator が正常に動作できません"
    echo "settings.toml の [Pulumi] セクションに access_token を設定してください"
    exit 1
fi

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
    while [ $timeout -gt 0 ]; do
        if kubectl get application platform -n argocd 2>/dev/null; then
            echo "✓ Platform Application作成確認"
            # 同期トリガー
            kubectl patch application platform -n argocd --type merge -p '{"operation": {"sync": {"syncStrategy": {"hook": {}}}}}'
            break
        fi
        echo "Platform Application作成待機中... (残り ${timeout}秒)"
        sleep 5
        timeout=$((timeout - 5))
    done
fi

# ClusterSecretStore準備完了待機
echo "ClusterSecretStore準備完了待機中..."
timeout=60
while [ $timeout -gt 0 ]; do
    if kubectl get clustersecretstore pulumi-esc-store 2>/dev/null | grep -q Ready; then
        echo "✓ ClusterSecretStore準備完了"
        break
    fi
    echo "ClusterSecretStore待機中... (残り ${timeout}秒)"
    sleep 5
    timeout=$((timeout - 5))
done

if [ $timeout -le 0 ]; then
    echo "エラー: ClusterSecretStore作成タイムアウト"
    echo "Pulumi ESC との接続が確立できませんでした"
    echo "Pulumi Access Token が正しいか確認してください"
    exit 1
else
    # External Secret同期待機（ArgoCD GitHub OAuth）
    timeout=60
    while [ $timeout -gt 0 ]; do
        if kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.dex\.github\.clientSecret}' 2>/dev/null | grep -q .; then
            SECRET_LENGTH=$(kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.dex\.github\.clientSecret}' | base64 -d | wc -c)
            if [ "$SECRET_LENGTH" -gt 10 ]; then
                echo "✓ ArgoCD GitHub OAuth ESO同期完了"
                break
            fi
        fi
        echo "External Secret同期待機中... (残り ${timeout}秒)"
        sleep 5
        timeout=$((timeout - 5))
    done
    
    if [ $timeout -le 0 ]; then
        echo "エラー: External Secret同期タイムアウト"
        echo "Pulumi ESC からのSecret取得に失敗しました"
        echo "Pulumi ESC の設定とキーが正しいか確認してください"
        exit 1
    fi
fi

# ArgoCD GitHub OAuth ConfigMapはGitOps経由で同期されます
echo "ArgoCD ConfigMapはPlatform Application経由で同期されます"

# ArgoCD サーバー再起動
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd --timeout=300s

echo "✓ ArgoCD GitHub OAuth設定完了"
EOF

print_status "✓ ArgoCD GitHub OAuth設定完了"

# Phase 4.8: Harbor デプロイ
print_status "=== Phase 4.8: Harbor デプロイ ==="
print_debug "Harbor Private Registry をArgoCD経由でデプロイします"

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
# Platform Application同期確認（External Secretsリソース適用のため）
if kubectl get application platform -n argocd 2>/dev/null; then
    echo "Platform Application同期確認中（Harbor External Secretsのため）..."
    kubectl patch application platform -n argocd --type merge -p '{"operation": {"sync": {"syncStrategy": {"hook": {}}}}}' || true
    kubectl wait --for=condition=Synced --timeout=300s application/platform -n argocd || echo "Platform同期継続中"
fi

# Harbor Application確認（App-of-Appsで作成される）
if kubectl get application harbor -n argocd 2>/dev/null; then
    echo "Harbor Application同期待機中..."
    kubectl wait --for=condition=Synced --timeout=300s application/harbor -n argocd || echo "Harbor同期継続中"
    
    # Harbor Pods起動待機
    echo "Harbor Pods起動待機中..."
    sleep 30
    kubectl wait --namespace harbor --for=condition=ready pod --selector=app=harbor --timeout=300s || echo "Harbor Pod起動待機中"
else
    echo "Harbor Application未作成、App-of-Apps確認中..."
    kubectl get application -n argocd
fi

echo "✓ Harbor デプロイ完了"
EOF

print_status "✓ Harbor デプロイ完了"

# Phase 4.8.5: Harbor認証設定（skopeo対応）
print_status "=== Phase 4.8.5: Harbor認証設定（skopeo対応） ==="
print_debug "Harbor認証情報secretをGitHub Actions用に設定します"

ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 << 'EOF'
# Harbor Pod起動待機
echo "Harbor Pod起動を待機中..."
if kubectl get pods -n harbor 2>/dev/null | grep -q harbor; then
    kubectl wait --namespace harbor --for=condition=ready pod --selector=app=harbor --timeout=300s || echo "Harbor起動待機中"
fi

# Pulumi ESC準備状況確認
PULUMI_TOKEN_EXISTS=$(kubectl get secret pulumi-esc-token -n external-secrets-system 2>/dev/null || echo "none")
if [[ "$PULUMI_TOKEN_EXISTS" == "none" ]]; then
    echo "エラー: Pulumi Access Tokenが設定されていません"
    echo "Harbor認証情報をExternal Secrets経由で取得できません"
    echo "settings.toml の [Pulumi] セクションに access_token を設定してください"
    exit 1
else
    # External Secretリソースの存在確認
    echo "Harbor External Secretリソース確認中..."
    if kubectl get externalsecret harbor-admin-secret -n harbor 2>/dev/null; then
        echo "✓ Harbor External Secret存在確認"
        # External Secretの同期をトリガー（kubectl annotateで更新）
        kubectl annotate externalsecret harbor-admin-secret -n harbor refresh=now --overwrite || true
    fi
fi

# ESO経由でharbor-admin-secretが作成されるまで待機
echo "harbor-admin-secretの作成を待機中 (ESO経由)..."
timeout=120
while [ $timeout -gt 0 ]; do
    if kubectl get secret harbor-admin-secret -n harbor 2>/dev/null | grep -q harbor-admin-secret; then
        # Secretが存在するか確認し、passwordフィールドがあるか確認
        if kubectl get secret harbor-admin-secret -n harbor -o jsonpath='{.data.password}' 2>/dev/null | grep -q .; then
            echo "✓ harbor-admin-secret作成確認"
            break
        fi
    fi
    echo "ESOにharbor-admin-secretを作成待機中... (残り ${timeout}秒)"
    sleep 5
    timeout=$((timeout - 5))
done

# Harbor管理者パスワード取得 (ESO経由のみ)
HARBOR_ADMIN_PASSWORD=$(kubectl get secret harbor-admin-secret -n harbor -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
if [[ -z "$HARBOR_ADMIN_PASSWORD" ]]; then
    echo "エラー: ESOからHarborパスワードを取得できませんでした"
    echo "External Secretsの同期が完了していません"
    echo "kubectl get externalsecret -n harbor で状態を確認してください"
    exit 1
fi

# arc-systems namespace作成（存在しない場合）
kubectl create namespace arc-systems --dry-run=client -o yaml | kubectl apply -f -

# arc-systems namespace の harbor-auth secret は GitOps経由で作成されます
echo "Harbor認証Secret (arc-systems) はGitOps経由で同期されます"

# 必要なネームスペースにHarbor Docker registry secret作成
NAMESPACES=("default" "sandbox" "production" "staging")

for namespace in "${NAMESPACES[@]}"; do
    # ネームスペース作成（存在しない場合）
    kubectl create namespace $namespace --dry-run=client -o yaml | kubectl apply -f -
    
    echo "harbor-http secret ($namespace) はGitOps経由で同期されます"
done

echo "✓ Harbor認証設定完了 - skopeo対応"
EOF

print_status "✓ Harbor認証設定（skopeo対応）完了"

# Phase 4.8.6: Worker ノード Containerd Harbor HTTP Registry設定
print_status "=== Phase 4.8.6: Containerd Harbor HTTP Registry設定 ==="
print_debug "各Worker ノードのContainerdにHarbor HTTP Registry設定を追加します"

# Harbor admin パスワード取得（ローカルで実行）
HARBOR_ADMIN_PASSWORD=$(ssh -T -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR k8suser@192.168.122.10 'kubectl get secret harbor-admin-secret -n harbor -o jsonpath="{.data.password}" 2>/dev/null | base64 -d')
if [[ -z "$HARBOR_ADMIN_PASSWORD" ]]; then
    print_error "ESOからHarborパスワードを取得できませんでした"
    print_error "External Secretsの同期が完了していません"
    print_error "kubectl get externalsecret -n harbor で状態を確認してください"
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

# Phase 4.9: GitHub Actions Runner Controller (ARC) セットアップ
print_status "=== Phase 4.9: GitHub Actions Runner Controller セットアップ ==="
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

# Phase 4.9.5: settings.tomlのリポジトリを自動add-runner
# この部分のエラーは無視して続行
(
    print_status "=== Phase 4.9.5: settings.tomlのリポジトリを自動add-runner ==="
    print_debug "settings.tomlからリポジトリリストを読み込み中..."

    SETTINGS_FILE="$SCRIPT_DIR/../settings.toml"
    if [[ -f "$SETTINGS_FILE" ]]; then
        # arc_repositoriesセクションを解析
        ARC_REPOS_TEMP=$(sed -n '/^arc_repositories = \[/,/^]/p' "$SETTINGS_FILE" | grep -E '^\s*\[".*"\s*,.*\]' || true)
        
        if [[ -n "$ARC_REPOS_TEMP" ]]; then
            print_debug "arc_repositories設定を発見しました"
            
            # リポジトリ数をカウント
            REPO_COUNT=$(echo "$ARC_REPOS_TEMP" | wc -l)
            print_debug "処理対象リポジトリ数: $REPO_COUNT"
            
            # 各リポジトリに対してadd-runner.shを実行
            PROCESSED=0
            FAILED=0
            CURRENT=0
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                
                # 正規表現で配列要素を抽出: ["name", min, max, "description"]
                if [[ $line =~ \[\"([^\"]+)\",\ *([0-9]+),\ *([0-9]+), ]]; then
                    REPO_NAME="${BASH_REMATCH[1]}"
                    MIN_RUNNERS="${BASH_REMATCH[2]}"
                    MAX_RUNNERS="${BASH_REMATCH[3]}"
                    ((CURRENT++))
                    
                    print_status "🏃 [$CURRENT/$REPO_COUNT] $REPO_NAME のRunnerを追加中... (min=$MIN_RUNNERS, max=$MAX_RUNNERS)"
                    
                    # add-runner.shを実行（エラーが発生しても継続）
                    if [[ -f "$SCRIPT_DIR/../scripts/github-actions/add-runner.sh" ]]; then
                        # エラーを無視して実行（stdinを保護）
                        if bash "$SCRIPT_DIR/../scripts/github-actions/add-runner.sh" "$REPO_NAME" 2>&1 < /dev/null; then
                            print_status "✓ $REPO_NAME Runner追加完了"
                            ((PROCESSED++))
                        else
                            print_error "❌ $REPO_NAME Runner追加失敗"
                            ((FAILED++))
                        fi
                        
                        # 次のRunner作成前に少し待機（API制限回避）
                        if [[ $CURRENT -lt $REPO_COUNT ]]; then
                            print_debug "次のRunner作成前に5秒待機中..."
                            sleep 5
                        fi
                    else
                        print_error "add-runner.sh が見つかりません"
                        # ファイルが見つからない場合は全て失敗とする
                        FAILED=$((REPO_COUNT - PROCESSED))
                        break
                    fi
                else
                    print_warning "⚠️ 解析できない行: $line"
                fi
            done <<< "$ARC_REPOS_TEMP"
            
            print_status "✓ settings.tomlのリポジトリ自動追加完了 (成功: $PROCESSED, 失敗: $FAILED)"
            
            # 失敗があった場合は警告
            if [[ $FAILED -gt 0 ]]; then
                print_warning "⚠️ $FAILED 個のリポジトリでRunner追加に失敗しました"
                print_warning "手動で 'make add-runner REPO=<name>' を実行してください"
            fi
        else
            print_debug "arc_repositories設定が見つかりません（スキップ）"
        fi
    else
        print_warning "settings.tomlが見つかりません"
    fi
) || print_warning "Runner自動追加でエラーが発生しましたが続行します"

# Phase 4.10: 各種Application デプロイ
print_status "=== Phase 4.10: 各種Application デプロイ ==="
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


# Phase 4.11: システム環境確認
print_status "=== Phase 4.11: システム環境確認 ==="
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