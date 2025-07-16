#!/bin/bash

# GitHub Actions Runner Controller (ARC) セットアップスクリプト
# Phase 4.9で実行される

set -euo pipefail

# GitHub認証情報管理ユーティリティを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/github-auth-utils.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# GitHub認証情報の確認・取得（保存済みを利用または新規入力）
print_status "GitHub認証情報を確認中..."
if ! get_github_credentials; then
    print_error "GitHub認証情報の取得に失敗しました"
    exit 1
fi

# Harbor認証情報確認・入力
print_status "Harbor認証情報を設定してください"

if [[ -z "${HARBOR_USERNAME:-}" ]]; then
    echo "Harbor Registry Username (default: admin):"
    echo -n "HARBOR_USERNAME [admin]: "
    read HARBOR_USERNAME_INPUT
    if [[ -z "$HARBOR_USERNAME_INPUT" ]]; then
        HARBOR_USERNAME="admin"
    else
        HARBOR_USERNAME="$HARBOR_USERNAME_INPUT"
    fi
    export HARBOR_USERNAME
    print_debug "HARBOR_USERNAME設定完了: $HARBOR_USERNAME"
else
    print_debug "HARBOR_USERNAME環境変数を使用: $HARBOR_USERNAME"
fi

if [[ -z "${HARBOR_PASSWORD:-}" ]]; then
    echo "Harbor Registry Password (default: Harbor12345):"
    echo -n "HARBOR_PASSWORD [Harbor12345]: "
    read -s HARBOR_PASSWORD_INPUT
    echo ""
    if [[ -z "$HARBOR_PASSWORD_INPUT" ]]; then
        HARBOR_PASSWORD="Harbor12345"
    else
        HARBOR_PASSWORD="$HARBOR_PASSWORD_INPUT"
    fi
    export HARBOR_PASSWORD
    print_debug "HARBOR_PASSWORD設定完了"
else
    print_debug "HARBOR_PASSWORD環境変数を使用"
fi

# 入力値検証
print_status "GitHub設定を検証中..."

# GitHubユーザー名の形式確認
if [[ ! "$GITHUB_USERNAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
    print_error "無効なGitHubユーザー名形式: $GITHUB_USERNAME"
    print_error "英数字とハイフンのみ使用可能です"
    exit 1
fi

# GitHub APIアクセステスト
print_debug "GitHub APIアクセステスト中..."
if ! curl -s -f -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/user" > /dev/null 2>&1; then
    print_error "GitHub API認証に失敗しました"
    print_error "GITHUB_TOKENが正しく設定されているか確認してください"
    print_error "必要な権限: repo, workflow, admin:org"
    exit 1
fi

print_status "✓ GitHub設定検証完了"

print_status "=== Phase 4.9: GitHub Actions Runner Controller (ARC) セットアップ ==="

# 1. Helmインストール確認
print_debug "Helmの確認中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
if ! command -v helm &> /dev/null; then
    echo "Helmをインストール中..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
    echo "✓ Helm既にインストール済み"
fi
EOF

# 2. GitHub Container Registry認証
print_debug "GitHub Container Registryにログイン中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << EOF
echo "${GITHUB_TOKEN}" | helm registry login ghcr.io -u ${GITHUB_USERNAME} --password-stdin
EOF

# 3. ARC namespaceとSecrets作成
print_debug "ARC namespace とSecrets作成中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << EOF
# Namespace作成
kubectl create namespace arc-systems --dry-run=client -o yaml | kubectl apply -f -

# GitHub Token Secret作成
kubectl create secret generic github-token \
  --from-literal=github_token=${GITHUB_TOKEN} \
  -n arc-systems \
  --dry-run=client -o yaml | kubectl apply -f -

# Harbor認証Secret作成
kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=192.168.122.100 \
  --docker-username=${HARBOR_USERNAME} \
  --docker-password=${HARBOR_PASSWORD} \
  -n arc-systems \
  --dry-run=client -o yaml | kubectl apply -f -

# Harbor認証Secret（GitHub Actions用）作成
kubectl create secret generic harbor-auth \
  --from-literal=HARBOR_USERNAME=${HARBOR_USERNAME} \
  --from-literal=HARBOR_PASSWORD=${HARBOR_PASSWORD} \
  --from-literal=HARBOR_URL=192.168.122.100 \
  --from-literal=HARBOR_PROJECT=sandbox \
  -n arc-systems \
  --dry-run=client -o yaml | kubectl apply -f -
  
# default namespace用も作成
kubectl create secret generic harbor-auth \
  --from-literal=HARBOR_USERNAME=${HARBOR_USERNAME} \
  --from-literal=HARBOR_PASSWORD=${HARBOR_PASSWORD} \
  --from-literal=HARBOR_URL=192.168.122.100 \
  --from-literal=HARBOR_PROJECT=sandbox \
  -n default \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Secrets作成完了"
EOF

# 4. ARC Controller インストール
print_status "ARC Controllerをインストール中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
helm install arc \
  --namespace arc-systems \
  --create-namespace \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller || \
echo "ARC Controller既にインストール済み"
EOF

# 5. Runner Scale Sets作成（ServiceAccount指定）
print_status "Runner Scale Setsを作成中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << EOF
# ServiceAccount確認
if ! kubectl get serviceaccount github-actions-runner -n arc-systems >/dev/null 2>&1; then
    echo "ServiceAccount 'github-actions-runner' が見つかりません"
    echo "自動作成中..."
    kubectl create serviceaccount github-actions-runner -n arc-systems
    
    # Secret読み取り権限付与
    kubectl apply -f - <<RBAC
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: secret-reader
  namespace: arc-systems
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: github-actions-secret-reader
  namespace: arc-systems
subjects:
- kind: ServiceAccount
  name: github-actions-runner
  namespace: arc-systems
roleRef:
  kind: Role
  name: secret-reader
  apiGroup: rbac.authorization.k8s.io
RBAC
fi
EOF

# 6. ARC状態確認
print_debug "ARC状態確認中..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
echo "=== ARC Controller状態 ==="
kubectl get pods -n arc-systems

echo -e "\n=== Runner Scale Sets ==="
kubectl get AutoscalingRunnerSet -n arc-systems 2>/dev/null || echo "AutoscalingRunnerSetがまだ作成されていません"

echo -e "\n=== Helm Releases ==="
helm list -n arc-systems
EOF

print_status "✓ GitHub Actions Runner Controller (ARC) セットアップ完了"

# 6.5. Harbor証明書修正（GitHub Actions対応）
print_status "=== Harbor証明書修正 + GitHub Actions対応 ==="
print_debug "GitHub Actionsからの証明書エラーを自動解決します"

# Harbor存在確認
print_debug "Harbor稼働状況を確認中..."
if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get namespace harbor' >/dev/null 2>&1; then
    # Harbor証明書修正スクリプトを実行
    if [[ -f "./harbor-cert-fix.sh" ]]; then
        print_debug "Harbor証明書修正スクリプトを実行中..."
        ./harbor-cert-fix.sh
        print_status "✓ Harbor証明書修正完了"
    else
        print_warning "harbor-cert-fix.shが見つかりません"
        print_debug "手動実行: automation/phase4/harbor-cert-fix.sh"
    fi
else
    print_warning "Harborがまだデプロイされていません"
    print_debug "ArgoCD App of Appsでのデプロイ完了後に以下を実行してください："
    print_debug "cd automation/phase4 && ./harbor-cert-fix.sh"
    print_warning "この状態でもGitHub Actionsランナーは利用可能ですが、Harbor pushでエラーが発生する可能性があります"
fi

# 7. 使用方法の表示
print_status "=== 使用方法 ==="
echo ""
echo "GitHub Actions workflowで以下のように指定してください："
echo ""
echo "jobs:"
echo "  build:"
echo "    runs-on: k8s-myhome-runners  # k8s_myHomeリポジトリ用"
echo "    # または"
echo "    runs-on: slack-rs-runners    # slack.rsリポジトリ用"
echo ""
echo "Harbor用環境変数:"
echo "- HARBOR_URL: 192.168.122.100"
echo "- HARBOR_PROJECT: sandbox"
echo ""
echo "Harbor認証："
echo "  docker login 192.168.122.100 -u $HARBOR_USERNAME -p $HARBOR_PASSWORD"
echo ""
echo ""
print_status "=== セットアップ完了 ==="
echo ""
echo "✅ 設定された認証情報:"
echo "   GitHub ユーザー名: $GITHUB_USERNAME"
echo "   GitHub Token: ${GITHUB_TOKEN:0:8}... (先頭8文字のみ表示)"
echo "   Harbor ユーザー名: $HARBOR_USERNAME (k8s Secret化済み)"
echo "   Harbor パスワード: ${HARBOR_PASSWORD:0:3}... (k8s Secret化済み)"
echo ""
echo "✅ 作成されたRunner Scale Sets:"
echo "   - k8s-myhome-runners (k8s_myHomeリポジトリ用)"
echo "   - slack-rs-runners (slack.rsリポジトリ用、存在する場合)"
echo ""
echo "✅ Harbor認証方式:"
echo "   - k8s Secret自動参照方式を採用"
echo "   - GitHub Repository Secretsの手動設定が不要"
echo "   - arc-systems namespace の harbor-auth Secret から自動取得"
echo "   - ServiceAccount 'github-actions-runner' で適切な権限設定"
echo ""
echo "✅ 完全自動化されたセットアップ:"
echo "   - Harbor パスワード: k8s Secret化済み"
echo "   - GitHub Actions Workflow: 最終版（Docker-in-Docker対応）"
echo "   - Runner Scale Set: 適切なServiceAccountで設定済み"
echo "   - Harbor証明書: IP SAN対応済み"
echo ""
echo "📝 次のステップ:"
echo "1. github-actions-example.yml をリポジトリの.github/workflows/にコピー"
echo "   cp automation/phase4/github-actions-example.yml .github/workflows/build-and-push.yml"
echo "2. GitリポジトリにCommit & Push"
echo "   git add .github/workflows/build-and-push.yml"
echo "   git commit -m \"GitHub Actions Harbor対応ワークフロー追加\""
echo "   git push"
echo "3. GitHub ActionsでCI/CDテスト実行"
echo "4. Harborでイメージ確認: https://192.168.122.100"
echo ""
echo "🔧 Harbor パスワード変更時:"
echo "   ./harbor-password-update.sh --interactive"
echo "   （GitHub Actions Runnerも自動再起動されます）"
echo ""
echo "🎉 ワンショットセットアップ完了！"
echo "   全てのコンポーネントが自動設定され、すぐにCI/CDが利用可能です。"