#!/bin/bash

# GitHub Actions Runner Controller (ARC) - 新しいリポジトリ用Runner追加スクリプト
# 公式GitHub ARC (v0.12.1) 対応版
# 使用方法: ./add-runner.sh <repository-name>

set -euo pipefail

# 共通ライブラリを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPTS_ROOT/common-k8s-utils.sh"
source "$SCRIPTS_ROOT/common-colors.sh"

# 引数確認
if [[ $# -lt 1 ]] || [[ $# -gt 2 ]]; then
    print_error "使用方法: $0 <repository-name> [--workflow-only]"
    print_error "例: $0 my-awesome-project"
    print_error "例: $0 my-awesome-project --workflow-only  # Workflowファイルのみ作成"
    exit 1
fi

REPOSITORY_NAME="$1"
WORKFLOW_ONLY="${2:-}"
# Runner名用（小文字変換、ドットとアンダースコアをハイフンに変換）
RUNNER_NAME="$(echo "${REPOSITORY_NAME}" | tr '[:upper:]._' '[:lower:]--')-runners"

print_status "=== GitHub Actions Runner追加スクリプト (公式ARC対応) ==="
print_debug "対象リポジトリ: $REPOSITORY_NAME"
print_debug "Runner名: $RUNNER_NAME"

# GitHub設定の取得
print_status "GitHub設定を取得中..."
SETTINGS_FILE="$SCRIPTS_ROOT/../settings.toml"
if [[ -f "$SETTINGS_FILE" ]]; then
    GITHUB_USERNAME=$(grep '^username = ' "$SETTINGS_FILE" | head -1 | cut -d'"' -f2)
    if [[ -z "$GITHUB_USERNAME" ]]; then
        print_error "settings.tomlのgithub.usernameが設定されていません"
        print_error "設定ファイル: $SETTINGS_FILE"
        exit 1
    fi
    print_debug "GitHub Username: $GITHUB_USERNAME (settings.tomlから取得)"
else
    print_error "settings.tomlが見つかりません: $SETTINGS_FILE"
    exit 1
fi

# GitHubリポジトリ存在確認（GitHub Token利用）
if [[ "$WORKFLOW_ONLY" != "--workflow-only" ]]; then
    print_debug "GitHubリポジトリ存在確認中..."
    if ! ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret github-token -n arc-systems' >/dev/null 2>&1; then
        print_error "GitHub認証情報が見つかりません。先にsetup-arc.shを実行してください"
        exit 1
    fi
    
    GITHUB_TOKEN=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret github-token -n arc-systems -o jsonpath="{.data.github_token}" | base64 -d')
    
    if ! curl -s -f -H "Authorization: token $GITHUB_TOKEN" \
      "https://api.github.com/repos/$GITHUB_USERNAME/$REPOSITORY_NAME" > /dev/null 2>&1; then
        print_error "GitHubリポジトリが見つかりません: $GITHUB_USERNAME/$REPOSITORY_NAME"
        print_error "リポジトリ名とアクセス権限を確認してください"
        print_error "Workflowファイルのみ作成する場合は --workflow-only オプションを使用してください"
        exit 1
    fi
    print_status "✓ GitHubリポジトリ確認完了: $GITHUB_USERNAME/$REPOSITORY_NAME"
fi

# k8sクラスタ接続確認
if [[ "$WORKFLOW_ONLY" != "--workflow-only" ]]; then
    print_debug "k8sクラスタ接続確認中..."
    if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
        print_error "k8sクラスタに接続できません"
        exit 1
    fi
    print_status "✓ k8sクラスタ接続OK"
fi

# Runner Scale Set作成（公式ARC対応）
if [[ "$WORKFLOW_ONLY" != "--workflow-only" ]]; then
    print_status "=== 新しいRunnerScaleSet作成 (公式GitHub ARC) ==="
    
    # 既存Runner確認とID競合チェック
    print_debug "既存Runner確認中..."
    EXISTING_RUNNER=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
        "helm list -n arc-systems | grep '$RUNNER_NAME' || echo ''")

    if [[ -n "$EXISTING_RUNNER" ]]; then
        print_warning "Runner '$RUNNER_NAME' は既に存在します"
        
        # ID競合の可能性をチェック
        print_debug "ID競合チェック中..."
        RUNNER_ID=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
            "kubectl get autoscalingrunnersets -n arc-systems '$RUNNER_NAME' -o jsonpath='{.metadata.annotations.runner-scale-set-id}' 2>/dev/null || echo ''")
        
        if [[ -n "$RUNNER_ID" ]]; then
            # 同じIDを使用している他のRunnerScaleSetがあるかチェック
            OTHER_RUNNERS=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
                "kubectl get autoscalingrunnersets -n arc-systems -o jsonpath='{range .items[*]}{.metadata.name}:{.metadata.annotations.runner-scale-set-id}{\"\\n\"}{end}' | grep ':$RUNNER_ID\$' | grep -v '^$RUNNER_NAME:' || echo ''")
            
            if [[ -n "$OTHER_RUNNERS" ]]; then
                print_warning "ID競合が検出されました (ID: $RUNNER_ID)"
                print_debug "競合するRunner: $OTHER_RUNNERS"
                print_warning "Runner '$RUNNER_NAME' を削除して新しいIDで再作成します"
                
                # 既存Runnerを削除
                ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "helm uninstall '$RUNNER_NAME' -n arc-systems"
                print_debug "既存Runner削除完了、新しいIDで再作成します"
                sleep 5  # GitHub API反映待機
            else
                echo -n "上書きしますか？ (y/N): "
                read -r OVERWRITE
                if [[ "$OVERWRITE" != "y" && "$OVERWRITE" != "Y" ]]; then
                    print_status "キャンセルしました"
                    exit 0
                fi
                print_debug "既存Runnerを上書きします"
            fi
        else
            echo -n "上書きしますか？ (y/N): "
            read -r OVERWRITE
            if [[ "$OVERWRITE" != "y" && "$OVERWRITE" != "Y" ]]; then
                print_status "キャンセルしました"
                exit 0
            fi
            print_debug "既存Runnerを上書きします"
        fi
    fi

    print_debug "Runner名: $RUNNER_NAME"
    print_debug "対象リポジトリ: https://github.com/$GITHUB_USERNAME/$REPOSITORY_NAME"

    # RunnerScaleSet作成（公式GitHub ARC）
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << EOF
echo "=== 新しいRunnerScaleSet '$RUNNER_NAME' を作成中 ==="

# Helmを使用して公式GitHub ARC RunnerScaleSetをインストール
helm upgrade --install $RUNNER_NAME \\
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \\
  --namespace arc-systems \\
  --set githubConfigUrl="https://github.com/$GITHUB_USERNAME/$REPOSITORY_NAME" \\
  --set githubConfigSecret="github-multi-repo-secret" \\
  --set maxRunners=3 \\
  --set minRunners=0 \\
  --set containerMode.type=dind \\
  --set template.spec.serviceAccountName=github-actions-runner

echo "✓ RunnerScaleSet '$RUNNER_NAME' 作成完了"
EOF

    # Runner状態確認
    print_debug "Runner状態確認中..."
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 << 'EOF'
echo "=== RunnerScaleSets 一覧 ==="
helm list -n arc-systems

echo -e "\n=== AutoscalingRunnerSet 状態 ==="
kubectl get AutoscalingRunnerSet -n arc-systems 2>/dev/null || echo "AutoscalingRunnerSetがまだ作成されていません（数秒待機してから再確認してください）"

echo -e "\n=== Runner Pods 状態 ==="
kubectl get pods -n arc-systems
EOF
    
    # 作成されたRunnerScaleSetのID確認
    print_debug "作成されたRunnerScaleSetのID確認中..."
    sleep 2  # AutoscalingRunnerSet作成待機
    NEW_RUNNER_ID=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
        "kubectl get autoscalingrunnersets -n arc-systems '$RUNNER_NAME' -o jsonpath='{.metadata.annotations.runner-scale-set-id}' 2>/dev/null || echo 'unknown'")
    
    if [[ "$NEW_RUNNER_ID" != "unknown" ]]; then
        print_status "✓ RunnerScaleSet '$RUNNER_NAME' セットアップ完了 (ID: $NEW_RUNNER_ID)"
        
        # ID重複の最終確認
        DUPLICATE_CHECK=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
            "kubectl get autoscalingrunnersets -n arc-systems -o jsonpath='{range .items[*]}{.metadata.name}:{.metadata.annotations.runner-scale-set-id}{\"\\n\"}{end}' | grep ':$NEW_RUNNER_ID\$' | wc -l")
        
        if [[ "$DUPLICATE_CHECK" -gt 1 ]]; then
            print_warning "⚠️ ID重複が検出されました。GitHubで手動確認が必要な場合があります"
        else
            print_debug "✓ ID重複なし、正常に作成されました"
        fi
    else
        print_warning "RunnerScaleSetは作成されましたが、IDの確認に失敗しました"
        print_status "✓ RunnerScaleSet '$RUNNER_NAME' セットアップ完了"
    fi
fi

# GitHub Actions workflow作成 (新ARC対応版)
print_status "=== GitHub Actions workflow作成 (新ARC対応) ==="

WORKFLOW_DIR=".github/workflows"
WORKFLOW_FILE="$WORKFLOW_DIR/build-and-push-$REPOSITORY_NAME.yml"

# .github/workflowsディレクトリ作成
mkdir -p "$WORKFLOW_DIR"
print_debug "Workflowディレクトリ作成: $WORKFLOW_DIR"

# workflow.yamlファイル作成 (新ARC対応版)
print_debug "Workflowファイル作成中: $WORKFLOW_FILE"
cat > "$WORKFLOW_FILE" << WORKFLOW_EOF
# GitHub Actions workflow for $REPOSITORY_NAME
# Auto-generated by add-runner.sh (公式ARC対応版)

name: Build and Push to Harbor - $REPOSITORY_NAME

on:
  push:
    branches: [ master, main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  build-and-push:
    runs-on: $RUNNER_NAME  # 新しいRunnerScaleSet
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
      
    - name: Setup kubectl and Harbor credentials
      run: |
        set -x  # デバッグモード有効化
        echo "=== Setup kubectl and Harbor credentials ==="
        
        # Install kubectl
        echo "Installing kubectl..."
        curl -LO "https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
        
        # Configure kubectl for in-cluster access
        echo "Configuring kubectl..."
        export KUBECONFIG=/tmp/kubeconfig
        kubectl config set-cluster default \\
            --server=https://kubernetes.default.svc \\
            --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \\
            --kubeconfig=\$KUBECONFIG
        kubectl config set-credentials default \\
            --token=\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) \\
            --kubeconfig=\$KUBECONFIG
        kubectl config set-context default \\
            --cluster=default --user=default \\
            --kubeconfig=\$KUBECONFIG
        kubectl config use-context default --kubeconfig=\$KUBECONFIG
        
        # Test kubectl connectivity
        echo "Testing kubectl connectivity..."
        kubectl get namespaces || echo "kubectl get namespaces failed"
        kubectl auth can-i get secrets -n arc-systems || echo "No kubectl secret permission"
        
        # List available secrets
        echo "Available secrets in arc-systems:"
        kubectl get secrets -n arc-systems || echo "Failed to list secrets"
        
        # Get Harbor credentials with proper JSON parsing
        echo "Getting Harbor credentials..."
        if kubectl get secret harbor-auth -n arc-systems >/dev/null 2>&1; then
            echo "harbor-auth secret exists"
            kubectl get secret harbor-auth -n arc-systems -o jsonpath='{.data.HARBOR_USERNAME}' | base64 -d > /tmp/harbor_username || echo "Failed to get HARBOR_USERNAME"
            kubectl get secret harbor-auth -n arc-systems -o jsonpath='{.data.HARBOR_PASSWORD}' | base64 -d > /tmp/harbor_password || echo "Failed to get HARBOR_PASSWORD"
            kubectl get secret harbor-auth -n arc-systems -o jsonpath='{.data.HARBOR_URL}' | base64 -d > /tmp/harbor_url || echo "Failed to get HARBOR_URL"
            kubectl get secret harbor-auth -n arc-systems -o jsonpath='{.data.HARBOR_PROJECT}' | base64 -d > /tmp/harbor_project || echo "Failed to get HARBOR_PROJECT"
        else
            echo "harbor-auth secret does NOT exist"
            exit 1
        fi
        
        # Debug file contents
        echo "harbor_username file content: \$(cat /tmp/harbor_username 2>/dev/null || echo 'empty')"
        echo "harbor_url file content: \$(cat /tmp/harbor_url 2>/dev/null || echo 'empty')"
        
        chmod 600 /tmp/harbor_* 2>/dev/null || echo "Failed to chmod harbor files"
        echo "✅ Harbor credentials retrieved successfully"
        
    - name: Build and push images using skopeo
      run: |
        echo "=== Build and push images using skopeo ==="
        
        HARBOR_USERNAME=\$(cat /tmp/harbor_username)
        HARBOR_PASSWORD=\$(cat /tmp/harbor_password)
        HARBOR_URL=\$(cat /tmp/harbor_url)
        HARBOR_PROJECT=\$(cat /tmp/harbor_project)
        
        # Debug Harbor credentials (without showing sensitive data)
        echo "Harbor URL: '\$HARBOR_URL'"
        echo "Harbor Project: '\$HARBOR_PROJECT'"
        echo "Harbor Username: '\$HARBOR_USERNAME'"
        
        # Validate variables are not empty
        if [ -z "\$HARBOR_URL" ] || [ -z "\$HARBOR_PROJECT" ] || [ -z "\$HARBOR_USERNAME" ]; then
          echo "❌ Harbor credentials are missing or empty"
          echo "URL: '\$HARBOR_URL', Project: '\$HARBOR_PROJECT', Username: '\$HARBOR_USERNAME'"
          exit 1
        fi
        
        # Install skopeo for Docker registry operations
        echo "Installing skopeo..."
        sudo apt-get update && sudo apt-get install -y skopeo
        
        # Build Docker images locally
        echo "Building Docker images..."
        docker build -t $REPOSITORY_NAME:latest .
        docker build -t $REPOSITORY_NAME:\${{ github.sha }} .
        
        # Push using skopeo with docker save/load approach
        echo "Pushing to Harbor using skopeo..."
        
        # Method 1: Try docker save with output redirect (more compatible)
        echo "Using docker save with output redirect..."
        docker save $REPOSITORY_NAME:latest > /tmp/$REPOSITORY_NAME-latest.tar
        docker save $REPOSITORY_NAME:\${{ github.sha }} > /tmp/$REPOSITORY_NAME-sha.tar
        
        # Push to Harbor using skopeo
        echo "Pushing images to Harbor..."
        skopeo copy --insecure-policy --dest-tls-verify=false \\
          --dest-creds="\$HARBOR_USERNAME:\$HARBOR_PASSWORD" \\
          docker-archive:/tmp/$REPOSITORY_NAME-latest.tar \\
          docker://\$HARBOR_URL/\$HARBOR_PROJECT/$REPOSITORY_NAME:latest
        
        skopeo copy --insecure-policy --dest-tls-verify=false \\
          --dest-creds="\$HARBOR_USERNAME:\$HARBOR_PASSWORD" \\
          docker-archive:/tmp/$REPOSITORY_NAME-sha.tar \\
          docker://\$HARBOR_URL/\$HARBOR_PROJECT/$REPOSITORY_NAME:\${{ github.sha }}
        
        echo "✅ Images pushed successfully to Harbor"
        
    - name: Verify Harbor repository
      run: |
        echo "=== Verify Harbor repository ==="
        
        HARBOR_USERNAME=\$(cat /tmp/harbor_username)
        HARBOR_PASSWORD=\$(cat /tmp/harbor_password)
        HARBOR_URL=\$(cat /tmp/harbor_url)
        HARBOR_PROJECT=\$(cat /tmp/harbor_project)
        
        # Verify pushed images via Harbor API (skip TLS verification)
        if curl -k -f -u "\$HARBOR_USERNAME:\$HARBOR_PASSWORD" "https://\$HARBOR_URL/v2/\$HARBOR_PROJECT/$REPOSITORY_NAME/tags/list"; then
          echo "✅ Harbor repository verified successfully"
        else
          echo "⚠️  Harbor API verification failed (images may still be available)"
        fi
        
        echo "✅ Deployment completed"
        
    - name: Cleanup
      if: always()
      run: |
        echo "=== Cleanup ==="
        
        # Remove sensitive credential files and temporary tar files
        rm -f /tmp/harbor_* /tmp/kubeconfig /tmp/$REPOSITORY_NAME-*.tar
        
        echo "✅ Cleanup completed"
WORKFLOW_EOF

# workflowファイル作成確認
if [[ -f "$WORKFLOW_FILE" ]]; then
    print_status "✅ Workflowファイル作成完了: $WORKFLOW_FILE"
else
    print_error "❌ Workflowファイル作成失敗: $WORKFLOW_FILE"
    exit 1
fi

print_status "=== セットアップ完了 ==="

# 現在のRunnerScaleSet一覧表示（ID競合確認のため）
if [[ "$WORKFLOW_ONLY" != "--workflow-only" ]]; then
    echo ""
    echo "📊 現在のRunnerScaleSet一覧 (ID競合確認):"
    ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 \
        "kubectl get autoscalingrunnersets -n arc-systems -o jsonpath='{range .items[*]}   - {.metadata.name}: ID {.metadata.annotations.runner-scale-set-id}{\"\\n\"}{end}'" 2>/dev/null || echo "   取得に失敗しました"
fi

echo ""
echo "✅ 作成されたRunnerScaleSet (公式GitHub ARC):"
echo "   - $RUNNER_NAME"
echo "   - リポジトリ: https://github.com/$GITHUB_USERNAME/$REPOSITORY_NAME"
echo "   - ServiceAccount: github-actions-runner"
echo "   - 最小Runner数: 0"
echo "   - 最大Runner数: 3"
echo "   - Docker-in-Docker対応"
echo ""
echo "✅ 作成されたGitHub Actions workflow (新ARC対応):"
echo "   - ファイル: $WORKFLOW_FILE"
echo "   - Runner: $RUNNER_NAME"
echo "   - Harbor認証とskopeo push対応（TLS検証無効）"
echo ""
echo "📝 次のステップ:"
echo "1. GitHub リポジトリに Commit & Push"
echo "   git add $WORKFLOW_FILE"
echo "   git commit -m \"Add GitHub Actions workflow for $REPOSITORY_NAME (公式ARC対応)\""
echo "   git push"
echo "2. GitHub ActionsでCI/CDテスト実行"
echo "3. Harborでイメージ確認: https://192.168.122.100"
echo ""
echo "🎉 $REPOSITORY_NAME 用のRunner環境が準備完了しました！"