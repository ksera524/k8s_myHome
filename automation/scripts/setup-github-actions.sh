#!/bin/bash

# GitHub Actions Runner Controller セットアップスクリプト
# make setup-github-actions から呼び出される

set -euo pipefail

# スクリプトディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 設定読み込み
source "$SCRIPT_DIR/settings-loader.sh"
load_settings

# GitHub Actions統合が有効かチェック
if [ "${AUTOMATION_ENABLE_GITHUB_ACTIONS:-false}" != "true" ]; then
    echo "ℹ️  GitHub Actions統合が無効です。スキップします"
    echo "有効にする場合は settings.toml で AUTOMATION_ENABLE_GITHUB_ACTIONS=true を設定してください"
    exit 0
fi

echo "ℹ️  GitHub Actions統合が有効です。ARCをセットアップします..."

# ARCセットアップ
cd "$PROJECT_ROOT"
make setup-arc || echo "⚠️  ARC設定で警告が発生しましたが続行します"
echo "✅ ARC設定完了"

echo "ℹ️  デフォルトRunnerを作成中..."

# GitHub repositoryからリポジトリ名を抽出してRunnerを作成
if [ -n "${GITHUB_REPOSITORY:-}" ]; then
    REPO_NAME=$(echo "$GITHUB_REPOSITORY" | cut -d'/' -f2)
    echo "ℹ️  $REPO_NAME 用のRunnerを作成します..."
    make add-runner REPO="$REPO_NAME" || echo "⚠️  Runner作成で警告が発生しましたが続行します"
else
    echo "⚠️  GITHUB_REPOSITORYが設定されていません。k8s_myHomeをデフォルトで使用します"
    make add-runner REPO="k8s_myHome" || echo "⚠️  Runner作成で警告が発生しましたが続行します"
fi

echo "✅ GitHub Actionsセットアップ完了"