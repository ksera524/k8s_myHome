#!/bin/bash
# add-runners-bulk.sh - settings.tomlのarc_repositoriesからRunner ScaleSetを一括作成

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ログ関数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_status() {
    echo -e "${BLUE}[STATUS]${NC} $1"
}

# settings.tomlからarc_repositoriesを読み取る
parse_arc_repositories() {
    local settings_file="$PROJECT_ROOT/automation/settings.toml"
    
    if [[ ! -f "$settings_file" ]]; then
        log_error "settings.tomlが見つかりません: $settings_file"
        exit 1
    fi
    
    # Python/tomlパッケージがあるか確認
    if command -v python3 &> /dev/null; then
        # Pythonでパース（tomlライブラリ不要の簡易パーサー）
        python3 <<EOF
import re
import sys

settings_file = "$settings_file"

try:
    with open(settings_file, "r") as f:
        content = f.read()
    
    # arc_repositoriesセクションを探す
    # マルチライン配列をサポート
    pattern = r'arc_repositories\s*=\s*\[(.*?)\](?:\s*$|\s*#|\s*\[)'
    match = re.search(pattern, content, re.DOTALL)
    
    if not match:
        sys.exit(0)
    
    repositories_text = match.group(1)
    
    # 各リポジトリエントリを抽出
    # ["repo", min, max, "description"] 形式
    repo_pattern = r'\[\s*"([^"]+)"\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*"([^"]*)"\s*\]'
    
    repos = re.findall(repo_pattern, repositories_text)
    
    if not repos:
        sys.exit(0)
    
    for repo_name, min_runners, max_runners, description in repos:
        print(f"{repo_name}|{min_runners}|{max_runners}|{description}")
            
except Exception as e:
    print(f"Error parsing settings.toml: {e}", file=sys.stderr)
    sys.exit(1)
EOF
    else
        # シンプルなgrep/sed/awkでのパース（制限あり）
        log_warning "Pythonが利用できません。簡易パースを使用します。"
        
        # arc_repositoriesセクションを抽出（簡易版）
        awk '/^arc_repositories = \[/,/^\]/' "$settings_file" | \
        grep -E '^\s*\[' | \
        sed 's/^\s*\[//; s/\],\?$//; s/"//g' | \
        while IFS=',' read -r repo min max desc; do
            # 前後の空白を削除
            repo=$(echo "$repo" | xargs)
            min=$(echo "$min" | xargs)
            max=$(echo "$max" | xargs)
            desc=$(echo "$desc" | xargs)
            
            if [[ -n "$repo" && -n "$min" && -n "$max" ]]; then
                echo "${repo}|${min}|${max}|${desc}"
            fi
        done
    fi
}

# メイン処理
main() {
    log_info "========================================="
    log_info "Runner ScaleSet一括作成開始"
    log_info "========================================="
    
    # settings.tomlからリポジトリリストを取得
    log_status "settings.tomlからarc_repositoriesを読み取り中..."
    
    repositories=()
    while IFS='|' read -r repo_name min_runners max_runners description; do
        repositories+=("$repo_name|$min_runners|$max_runners|$description")
    done < <(parse_arc_repositories)
    
    if [[ ${#repositories[@]} -eq 0 ]]; then
        log_warning "arc_repositoriesが設定されていません。"
        log_info "settings.tomlの[github]セクションにarc_repositoriesを設定してください。"
        exit 0
    fi
    
    log_info "合計 ${#repositories[@]} 個のリポジトリが見つかりました。"
    echo ""
    
    # 各リポジトリに対してadd-runner.shを実行
    success_count=0
    failed_count=0
    failed_repos=()
    
    for repo_entry in "${repositories[@]}"; do
        IFS='|' read -r repo_name min_runners max_runners description <<< "$repo_entry"
        
        log_info "-----------------------------------------"
        log_info "リポジトリ: $repo_name"
        log_info "説明: ${description:-設定なし}"
        log_info "Runner設定: min=$min_runners, max=$max_runners"
        log_status "Runner ScaleSet作成中..."
        
        # add-runner.shを実行（サブシェルで実行して親シェルへの影響を防ぐ）
        set +e
        (
            "$SCRIPT_DIR/add-runner.sh" "$repo_name" "$min_runners" "$max_runners"
        )
        result=$?
        set -e
        
        if [[ $result -eq 0 ]]; then
            log_info "✓ $repo_name のRunner ScaleSet作成成功"
            success_count=$((success_count + 1))
        else
            log_error "✗ $repo_name のRunner ScaleSet作成失敗 (exit code: $result)"
            failed_repos+=("$repo_name")
            failed_count=$((failed_count + 1))
        fi
        
        echo ""
    done
    
    # 結果サマリー
    log_info "========================================="
    log_info "Runner ScaleSet一括作成完了"
    log_info "========================================="
    log_info "成功: $success_count / ${#repositories[@]}"
    
    if [[ $failed_count -gt 0 ]]; then
        log_warning "失敗: $failed_count"
        log_warning "失敗したリポジトリ:"
        for repo in "${failed_repos[@]}"; do
            echo "  - $repo"
        done
        exit 1
    else
        log_info "すべてのRunner ScaleSetが正常に作成されました。"
    fi
}

# スクリプト実行
main "$@"