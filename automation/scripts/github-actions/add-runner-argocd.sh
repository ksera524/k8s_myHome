#!/bin/bash

# GitHub Actions Runner Controller (ARC) - ArgoCD Application作成版
# Runnerを永続化するためにArgoCDで管理

set -euo pipefail

# 共通ライブラリを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPTS_ROOT/common-k8s-utils.sh"
source "$SCRIPTS_ROOT/common-colors.sh"

# 引数確認
if [[ $# -lt 1 ]]; then
    print_error "使用方法: $0 <repository-name> [min-runners] [max-runners]"
    print_error "例: $0 my-awesome-project 1 3"
    exit 1
fi

REPOSITORY_NAME="$1"
# デフォルト値を設定（引数が渡されない場合）
MIN_RUNNERS="${2:-1}"
MAX_RUNNERS="${3:-3}"
# Runner名生成（小文字変換、ドット・アンダースコアをハイフンに変換）
RUNNER_NAME="$(echo "${REPOSITORY_NAME}" | tr '[:upper:]._' '[:lower:]--')-runners"

print_status "=== GitHub Actions Runner追加スクリプト (ArgoCD版) ==="
print_debug "対象リポジトリ: $REPOSITORY_NAME"
print_debug "Runner名: $RUNNER_NAME"
print_debug "Min Runners: $MIN_RUNNERS"
print_debug "Max Runners: $MAX_RUNNERS"

# GitHubユーザー名を取得（settings.tomlから）
SETTINGS_FILE="$SCRIPTS_ROOT/../settings.toml"
if [[ ! -f "$SETTINGS_FILE" ]]; then
    SETTINGS_FILE="$SCRIPTS_ROOT/../../settings.toml"
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        SETTINGS_FILE="$(dirname "$SCRIPTS_ROOT")/settings.toml"
        if [[ ! -f "$SETTINGS_FILE" ]]; then
            print_error "settings.tomlが見つかりません"
            print_error "automation/settings.tomlを作成してください"
            exit 1
        fi
    fi
fi

print_debug "settings.tomlファイル: $SETTINGS_FILE"
GITHUB_USERNAME=$(grep '^username = ' "$SETTINGS_FILE" | head -1 | cut -d'"' -f2)
if [[ -z "$GITHUB_USERNAME" ]]; then
    print_error "settings.tomlのgithub.usernameが設定されていません"
    print_error "ファイル: $SETTINGS_FILE"
    exit 1
fi
print_debug "GitHub Username: $GITHUB_USERNAME"

# k8sクラスタ接続確認
print_debug "k8sクラスタ接続確認中..."
if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
    print_error "k8sクラスタに接続できません"
    exit 1
fi
print_status "✓ k8sクラスタ接続OK"

# GitHub認証情報確認
print_debug "GitHub認証情報確認中..."
if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret github-auth -n arc-systems' >/dev/null 2>&1; then
    print_error "GitHub認証情報が見つかりません。make all を実行してください"
    exit 1
fi
print_status "✓ GitHub認証情報確認完了"

# GitHub multi-repo secret確認/作成
print_debug "GitHub multi-repo secret確認中..."
if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret github-multi-repo-secret -n arc-systems' >/dev/null 2>&1; then
    print_debug "github-multi-repo-secret を作成中..."
    GITHUB_TOKEN=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret github-auth -n arc-systems -o jsonpath="{.data.GITHUB_TOKEN}" | base64 -d')
    if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl create secret generic github-multi-repo-secret --from-literal=github_token='$GITHUB_TOKEN' -n arc-systems"; then
        print_debug "✓ github-multi-repo-secret 作成完了"
    else
        print_warning "⚠️ github-multi-repo-secret は既に存在するか、作成に失敗しました"
    fi
else
    print_debug "✓ github-multi-repo-secret 確認済み"
fi

# ArgoCD Application YAML作成
print_status "🏃 ArgoCD Application作成中..."
MANIFEST_DIR="/home/ksera/k8s_myHome/manifests/platform/ci-cd/github-actions"
RUNNERS_FILE="$MANIFEST_DIR/runners.yaml"

# 既存のrunners.yamlを読み込み（存在しない場合は作成）
if [[ ! -f "$RUNNERS_FILE" ]]; then
    cat > "$RUNNERS_FILE" << 'HEADER'
# GitHub Actions Runners
# settings.tomlで定義されたリポジトリのRunnerをArgoCD管理下に配置
# 
# 重要: このファイルはadd-runner-argocd.shによって自動生成/更新されます
# 手動で編集しないでください
HEADER
fi

# 既存のRunnerがあるかチェック
if grep -q "name: $RUNNER_NAME" "$RUNNERS_FILE" 2>/dev/null; then
    print_warning "既存の $RUNNER_NAME を更新中..."
    # 既存のエントリを削除（簡易的な実装）
    # TODO: より堅牢な実装にする
fi

# 新しいApplication定義を追加
cat >> "$RUNNERS_FILE" << APPLICATION_EOF

# $REPOSITORY_NAME Runner
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $RUNNER_NAME
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ghcr.io/actions/actions-runner-controller-charts
    targetRevision: 0.12.1
    chart: gha-runner-scale-set
    helm:
      values: |
        githubConfigUrl: https://github.com/$GITHUB_USERNAME/$REPOSITORY_NAME
        githubConfigSecret: github-multi-repo-secret
        minRunners: $MIN_RUNNERS
        maxRunners: $MAX_RUNNERS
        containerMode:
          type: dind
        template:
          spec:
            serviceAccountName: github-actions-runner
  
  destination:
    server: https://kubernetes.default.svc
    namespace: arc-systems
  
  syncPolicy:
    automated:
      prune: false  # 重要: Runnerは削除しない
      selfHeal: true
    syncOptions:
      - CreateNamespace=false  # 既にnamespaceは存在する
APPLICATION_EOF

print_status "✓ ArgoCD Application定義を追加: $RUNNERS_FILE"

# GitでコミットとプッシュのためのHELP表示
print_status "=== セットアップ完了 ==="
print_status ""
print_status "✅ ArgoCD Application作成:"
print_status "   - $RUNNER_NAME (minRunners=$MIN_RUNNERS, maxRunners=$MAX_RUNNERS)"
print_status "   - リポジトリ: https://github.com/$GITHUB_USERNAME/$REPOSITORY_NAME"
print_status ""
print_status "📝 次のステップ:"
print_status "1. Gitにコミット & Push"
print_status "   cd /home/ksera/k8s_myHome"
print_status "   git add manifests/platform/ci-cd/github-actions/runners.yaml"
print_status "   git commit -m \"Add GitHub Actions runner for $REPOSITORY_NAME\""
print_status "   git push"
print_status ""
print_status "2. ArgoCDが自動的にRunnerをデプロイします（1-2分待機）"
print_status ""
print_status "3. 状態確認:"
print_status "   kubectl get applications -n argocd | grep $RUNNER_NAME"
print_status "   kubectl get autoscalingrunnersets -n arc-systems"
print_status ""
print_status "🎉 $REPOSITORY_NAME 用のRunnerがArgoCDで管理されます！"