#!/bin/bash

# settings.tomlからGitHub Actions Runnerをデプロイするスクリプト
# platform-deploy.shのPhase 4.9.5と同じ処理を単独で実行

set -euo pipefail

# 共通ライブラリを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPTS_ROOT/common-colors.sh"

print_status "=== settings.tomlからGitHub Actions Runnerをデプロイ ==="

# settings.tomlを探す
SETTINGS_FILE="$SCRIPTS_ROOT/../settings.toml"
if [[ ! -f "$SETTINGS_FILE" ]]; then
    print_error "settings.tomlが見つかりません: $SETTINGS_FILE"
    exit 1
fi

print_status "settings.tomlが見つかりました: $SETTINGS_FILE"

# arc_repositoriesセクションを解析
ARC_REPOS_TEMP=$(awk '/^arc_repositories = \[/,/^\]/' "$SETTINGS_FILE" | grep -E '^\s*\["' | grep -v '^arc_repositories' || true)

if [[ -z "$ARC_REPOS_TEMP" ]]; then
    print_warning "arc_repositories設定が見つかりません"
    exit 0
fi

print_status "arc_repositories設定を発見しました:"
echo "$ARC_REPOS_TEMP"

# リポジトリ数をカウント
REPO_COUNT=$(echo "$ARC_REPOS_TEMP" | wc -l)
print_status "処理対象リポジトリ数: $REPO_COUNT"

# SSH接続確認
print_status "k8sクラスタ接続確認中..."
if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
    print_error "k8sクラスタに接続できません"
    exit 1
fi
print_status "✓ k8sクラスタ接続OK"

# 各リポジトリに対してadd-runner.shを実行
PROCESSED=0
FAILED=0
CURRENT=0

while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    
    # 正規表現で配列要素を抽出
    if [[ $line =~ \[\"([^\"]+)\"[[:space:]]*,[[:space:]]*([0-9]+)[[:space:]]*,[[:space:]]*([0-9]+)[[:space:]]*,[[:space:]]*\"[^\"]*\"\] ]]; then
        REPO_NAME="${BASH_REMATCH[1]}"
        MIN_RUNNERS="${BASH_REMATCH[2]}"
        MAX_RUNNERS="${BASH_REMATCH[3]}"
        CURRENT=$((CURRENT+1))
        
        print_status "🏃 [$CURRENT/$REPO_COUNT] $REPO_NAME のRunnerを追加中..."
        print_debug "  Min: $MIN_RUNNERS, Max: $MAX_RUNNERS"
        
        # add-runner.shを実行
        ADD_RUNNER_SCRIPT="$SCRIPT_DIR/add-runner.sh"
        if [[ -f "$ADD_RUNNER_SCRIPT" ]]; then
            print_debug "Executing: bash $ADD_RUNNER_SCRIPT $REPO_NAME $MIN_RUNNERS $MAX_RUNNERS"
            if bash "$ADD_RUNNER_SCRIPT" "$REPO_NAME" "$MIN_RUNNERS" "$MAX_RUNNERS" < /dev/null; then
                print_status "✓ $REPO_NAME Runner追加完了"
                PROCESSED=$((PROCESSED+1))
            else
                EXIT_CODE=$?
                print_error "❌ $REPO_NAME Runner追加失敗 (exit code: $EXIT_CODE)"
                FAILED=$((FAILED+1))
            fi
            
            # 次のRunner作成前に少し待機
            if [[ $CURRENT -lt $REPO_COUNT ]]; then
                print_debug "次のRunner作成前に5秒待機中..."
                sleep 5
            fi
        else
            print_error "add-runner.sh が見つかりません: $ADD_RUNNER_SCRIPT"
            FAILED=$((REPO_COUNT - PROCESSED))
            break
        fi
    else
        print_warning "解析できない行: $line"
    fi
done <<< "$ARC_REPOS_TEMP"

print_status "=== デプロイ結果 ==="
print_status "成功: $PROCESSED"
if [[ $FAILED -gt 0 ]]; then
    print_error "失敗: $FAILED"
fi

# 状態確認
print_status "=== 現在の状態 ==="
echo "AutoscalingRunnerSets:"
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get autoscalingrunnersets -n arc-systems 2>/dev/null' || echo "AutoscalingRunnerSets未作成"
echo ""
echo "Runner Pods:"
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get pods -n arc-systems -l app.kubernetes.io/name=runner 2>/dev/null' || echo "Runner Pods未起動"
echo ""
echo "Helm Releases:"
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'helm list -n arc-systems 2>/dev/null' || echo "Helm Releases未作成"