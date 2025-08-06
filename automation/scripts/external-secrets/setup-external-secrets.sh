#!/bin/bash

# External Secrets Operator セットアップスクリプト
# k8s_myHome用の段階的導入自動化

set -euo pipefail

# スクリプトディレクトリ取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 共通色設定スクリプトを読み込み
source "$SCRIPT_DIR/../common-colors.sh"

print_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# 現在のディレクトリを確認
if [[ ! -d "../../../manifests/external-secrets" ]]; then
    print_error "manifests/external-secrets ディレクトリが見つかりません"
    print_error "automation/platform/external-secrets から実行してください"
    exit 1
fi

print_status "=== External Secrets Operator セットアップ開始 ==="

# Phase 1: App-of-Apps更新確認
print_status "Phase 1: ArgoCD Application設定確認"

APP_OF_APPS_FILE="../../../manifests/app-of-apps.yaml"
if grep -q "external-secrets-operator" "$APP_OF_APPS_FILE"; then
    print_debug "external-secrets-operator はすでにapp-of-apps.yamlに登録済み"
else
    print_warning "app-of-apps.yamlにexternal-secrets-operatorを追加する必要があります"
    print_debug "手動で以下を $APP_OF_APPS_FILE に追加してください："
    cat << 'EOF'
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-secrets-operator
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/ksera524/k8s_myHome.git
    targetRevision: HEAD
    path: manifests/external-secrets
    directory:
      include: "external-secrets-operator-app.yaml"
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
fi

# Phase 2: ArgoCD Application同期待機
print_status "Phase 2: ArgoCD Application同期待機"

print_debug "ArgoCD Applicationの作成を待機中..."
timeout=300
while [ $timeout -gt 0 ]; do
    if kubectl get application external-secrets-operator -n argocd >/dev/null 2>&1; then
        print_status "✓ ArgoCD Application作成確認"
        break
    fi
    echo "ArgoCD Application作成待機中... (残り ${timeout}秒)"
    sleep 10
    timeout=$((timeout - 10))
done

if [ $timeout -le 0 ]; then
    print_error "ArgoCD Application作成がタイムアウトしました"
    print_error "手動でapp-of-apps.yamlの更新とArgoCD同期を確認してください"
    exit 1
fi

# Phase 3: ESO Pod起動待機
print_status "Phase 3: External Secrets Operator Pod起動待機"

print_debug "ESO Controller Pod起動を待機中..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=external-secrets \
    -n external-secrets-system \
    --timeout=300s

if [ $? -eq 0 ]; then
    print_status "✓ External Secrets Operator起動完了"
else
    print_error "External Secrets Operator起動に失敗しました"
    print_debug "ESO Pod状態:"
    kubectl get pods -n external-secrets-system
    exit 1
fi

# Phase 4: CRD確認
print_status "Phase 4: Custom Resource Definition確認"

REQUIRED_CRDS=(
    "externalsecrets.external-secrets.io"
    "secretstores.external-secrets.io"
    "clustersecretstores.external-secrets.io"
)

for crd in "${REQUIRED_CRDS[@]}"; do
    if kubectl get crd "$crd" >/dev/null 2>&1; then
        print_status "✓ CRD確認: $crd"
    else
        print_error "✗ CRD未確認: $crd"
        exit 1
    fi
done

# Phase 5: 基本動作確認
print_status "Phase 5: 基本動作確認"

print_debug "ESO Controller バージョン確認:"
kubectl get deployment external-secrets -n external-secrets-system \
    -o jsonpath='{.spec.template.spec.containers[0].image}'
echo ""

print_debug "ESO Controller ログ確認（最新10行）:"
kubectl logs -n external-secrets-system deployment/external-secrets --tail=10

# Phase 6: Pulumi ESC認証設定
print_status "Phase 6: Pulumi ESC認証設定"

# Pulumi Access Token の設定確認
if kubectl get secret pulumi-access-token -n external-secrets-system >/dev/null 2>&1; then
    print_status "✓ Pulumi Access Token は既に設定済みです"
else
    print_warning "Pulumi Access Token が設定されていません"
    
    # 対話的にPATを設定するかユーザーに確認
    echo -n "今すぐPulumi Access Tokenを設定しますか？ [Y/n]: "
    read -r response
    case "$response" in
        [nN][oO]|[nN])
            print_debug "Pulumi Access Token設定をスキップします"
            ;;
        *)
            print_status "Pulumi Access Token設定を開始します"
            if [[ -f "setup-pulumi-pat.sh" ]]; then
                ./setup-pulumi-pat.sh --interactive
                if [ $? -eq 0 ]; then
                    print_status "✓ Pulumi Access Token設定完了"
                else
                    print_warning "Pulumi Access Token設定に失敗しました"
                fi
            else
                print_error "setup-pulumi-pat.sh が見つかりません"
            fi
            ;;
    esac
fi

# Phase 7: SecretStore設定
print_status "Phase 7: SecretStore設定"

if kubectl get secret pulumi-access-token -n external-secrets-system >/dev/null 2>&1; then
    print_debug "SecretStore設定を適用中..."
    if kubectl apply -f secretstores/pulumi-esc-secretstore.yaml >/dev/null 2>&1; then
        print_status "✓ SecretStore設定完了"
        
        # SecretStore接続確認
        print_debug "SecretStore接続確認中..."
        timeout=60
        while [ $timeout -gt 0 ]; do
            SECRETSTORE_STATUS=$(kubectl get secretstore pulumi-esc-store -n harbor -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
            if [ "$SECRETSTORE_STATUS" = "True" ]; then
                print_status "✓ SecretStore接続確認完了"
                break
            fi
            echo "SecretStore接続待機中... (残り ${timeout}秒)"
            sleep 5
            timeout=$((timeout - 5))
        done
        
        if [ $timeout -le 0 ]; then
            print_warning "SecretStore接続確認がタイムアウトしました"
            print_debug "手動確認: kubectl describe secretstore pulumi-esc-store -n harbor"
        fi
    else
        print_error "SecretStore設定に失敗しました"
    fi
else
    print_warning "Pulumi Access Tokenが設定されていないため、SecretStore設定をスキップします"
fi

# Phase 8: セットアップ完了案内
print_status "Phase 8: セットアップ完了"

cat << EOF

${GREEN}✅ External Secrets Operatorセットアップ完了${NC}

${YELLOW}次のステップ:${NC}
1. Harbor Secret自動デプロイ:
   ${BLUE}./deploy-harbor-secrets.sh${NC}

2. 動作確認:
   ${BLUE}./test-harbor-secrets.sh${NC}

${YELLOW}automation統合:${NC}
- k8s-infrastructure-deploy.sh が自動的に External Secrets を使用します
- 従来の create-harbor-secrets.sh は不要になります

${YELLOW}確認コマンド:${NC}
- ESO状態確認: ${BLUE}kubectl get pods -n external-secrets-system${NC}
- PAT設定確認: ${BLUE}kubectl get secrets -A | grep pulumi-access-token${NC}
- SecretStore確認: ${BLUE}kubectl get secretstores -A${NC}
- Harbor Secrets確認: ${BLUE}kubectl get externalsecrets -A${NC}

${YELLOW}手動でPulumi Access Tokenを設定する場合:${NC}
${BLUE}./setup-pulumi-pat.sh --interactive${NC}

EOF

print_status "=== セットアップ完了 ==="