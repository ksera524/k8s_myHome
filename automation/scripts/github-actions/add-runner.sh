#!/usr/bin/env bash

# GitHub Actions Runner Controller (ARC) - 新しいリポジトリ用Runner追加スクリプト

set -euo pipefail

# 共通ライブラリを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "$SCRIPTS_ROOT/common-logging.sh"

# 引数確認
if [[ $# -ne 4 ]]; then
    log_error "使用方法: $0 <repository-name> <min-runners> <max-runners> <strategy>"
    log_error "例: $0 my-awesome-project 1 3 latest"
    log_error "strategy は latest のみ指定可能です"
    exit 1
fi

REPOSITORY_NAME="$1"
MIN_RUNNERS="$2"
MAX_RUNNERS="$3"
WORKFLOW_STRATEGY="$4"

# Runner名生成（小文字変換、ドット・アンダースコアをハイフンに変換）
RUNNER_SLUG="$(echo "${REPOSITORY_NAME}" | tr '[:upper:]._' '[:lower:]--')"
RUNNER_NAME="${RUNNER_SLUG}-runners"
IMAGE_NAME="$(echo "${REPOSITORY_NAME}" | tr '[:upper:]' '[:lower:]')"

if [[ "$WORKFLOW_STRATEGY" != "latest" ]]; then
    log_error "strategy は latest のみ指定可能です: $WORKFLOW_STRATEGY"
    exit 1
fi

log_status "=== GitHub Actions Runner追加スクリプト (公式ARC対応) ==="
log_debug "対象リポジトリ: $REPOSITORY_NAME"
log_debug "Runner名: $RUNNER_NAME"
log_debug "Min Runners: $MIN_RUNNERS"
log_debug "Max Runners: $MAX_RUNNERS"
log_debug "Workflow Strategy: $WORKFLOW_STRATEGY"

# GitHubユーザー名を取得（settings.tomlから）
SETTINGS_FILE="$SCRIPTS_ROOT/../settings.toml"
if [[ ! -f "$SETTINGS_FILE" ]]; then
    SETTINGS_FILE="$SCRIPTS_ROOT/../../settings.toml"
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        SETTINGS_FILE="$(dirname "$SCRIPTS_ROOT")/settings.toml"
        if [[ ! -f "$SETTINGS_FILE" ]]; then
            log_error "settings.tomlが見つかりません"
            log_error "automation/settings.tomlを作成してください"
            exit 1
        fi
    fi
fi

log_debug "settings.tomlファイル: $SETTINGS_FILE"
GITHUB_USERNAME=$(grep '^username = ' "$SETTINGS_FILE" | head -1 | cut -d'"' -f2)
if [[ -z "$GITHUB_USERNAME" ]]; then
    # 後方互換: repository = "owner/repo" からownerを導出
    GITHUB_USERNAME=$(grep '^repository = ' "$SETTINGS_FILE" | head -1 | cut -d'"' -f2 | cut -d'/' -f1)
fi
if [[ -z "$GITHUB_USERNAME" ]]; then
    log_error "settings.tomlのgithub.usernameが設定されていません"
    log_error "ファイル: $SETTINGS_FILE"
    exit 1
fi
log_debug "GitHub Username: $GITHUB_USERNAME"

PROJECT_ROOT="$(cd "$SCRIPTS_ROOT/../.." && pwd)"
APPSET_FILE="$PROJECT_ROOT/manifests/platform/ci-cd/github-actions/runners-appset.yaml"

if [[ ! -f "$APPSET_FILE" ]]; then
    log_error "ApplicationSet定義が見つかりません: $APPSET_FILE"
    exit 1
fi

log_status "=== Runner定義をGitOps管理へ登録 ==="
UPSERT_RESULT=$(python3 - <<PY
import re
from pathlib import Path
import yaml
import sys

appset_path = Path(r"$APPSET_FILE")
repo_name = r"$REPOSITORY_NAME"
min_runners = str(r"$MIN_RUNNERS")
max_runners = str(r"$MAX_RUNNERS")
github_owner = r"$GITHUB_USERNAME"

text = appset_path.read_text(encoding="utf-8")
doc = yaml.safe_load(text)
elements = doc["spec"]["generators"][0]["list"]["elements"]

slug = re.sub(r"[._]", "-", repo_name.lower())
entry = {
    "name": slug,
    "githubOwner": github_owner,
    "githubRepo": repo_name,
    "runnerName": f"{slug}-runners",
    "minRunners": min_runners,
    "maxRunners": max_runners,
    "workflowStrategy": "latest",
}

updated = False
result = "unchanged"
for i, e in enumerate(elements):
    if e.get("runnerName") == entry["runnerName"] or e.get("githubRepo") == repo_name:
        if e != entry:
            elements[i] = entry
            updated = True
        result = "updated" if updated else "unchanged"
        break
else:
    elements.append(entry)
    updated = True
    result = "added"

if updated:
    lines = text.splitlines(keepends=True)
    elem_idx = None
    elem_indent = 6
    for i, line in enumerate(lines):
        match = re.match(r"^(\s*)elements:\s*$", line)
        if match:
            elem_idx = i
            elem_indent = len(match.group(1))
            break
    if elem_idx is None:
        print("runners-appset.yaml に elements: が見つかりません", file=sys.stderr)
        sys.exit(1)

    end_idx = len(lines)
    for i in range(elem_idx + 1, len(lines)):
        stripped = lines[i].lstrip()
        if stripped.startswith("#") or not stripped.strip():
            continue
        indent = len(lines[i]) - len(stripped)
        if indent < elem_indent:
            end_idx = i
            break

    # elements領域のみを再シリアライズする（ファイル全体は safe_dump しない:
    # values: | ブロックスカラー等が壊れるため）
    prefix = " " * elem_indent
    if elements:
        region = f"{prefix}elements:\n"
        dumped = yaml.safe_dump(elements, sort_keys=False, allow_unicode=False).splitlines()
        for line in dumped:
            if line.startswith("elements:"):
                continue
            region += prefix + line + "\n"
    else:
        region = f"{prefix}elements: []\n"

    new_lines = lines[:elem_idx] + [region] + lines[end_idx:]
    appset_path.write_text("".join(new_lines), encoding="utf-8")

print(result)
PY
)

case "$UPSERT_RESULT" in
    added)
        log_status "✓ Runner定義を追加しました: $REPOSITORY_NAME"
        ;;
    updated)
        log_status "✓ Runner定義を更新しました: $REPOSITORY_NAME"
        ;;
    unchanged)
        log_status "✓ Runner定義は最新です: $REPOSITORY_NAME"
        ;;
    *)
        log_error "Runner定義の更新に失敗しました"
        exit 1
        ;;
esac

log_status "ℹ️ Runner本体はArgoCD(ApplicationSet)経由でデプロイされます"
log_status "ℹ️ 反映にはこのリポジトリのcommit/pushが必要です"

# GitHub Actions workflow作成
log_status "=== GitHub Actions workflow作成 ==="

WORKFLOW_DIR=".github/workflows"
WORKFLOW_FILE="$WORKFLOW_DIR/build-and-push-$REPOSITORY_NAME.yml"

mkdir -p "$WORKFLOW_DIR"
log_debug "Workflowディレクトリ作成: $WORKFLOW_DIR"

cat > "$WORKFLOW_FILE" << WORKFLOW_EOF
# GitHub Actions workflow for $REPOSITORY_NAME
# Auto-generated by add-runner.sh (公式ARC対応版) - latest運用

name: Build and Push to Harbor - $REPOSITORY_NAME

on:
  push:
    branches: [ main, master ]
  pull_request:
    branches: [ main, master ]

env:
  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: "true"

concurrency:
  group: build-push-\${{ github.workflow }}-\${{ github.ref }}
  cancel-in-progress: false

permissions:
  contents: read
  pull-requests: read

jobs:
  build-image:
    runs-on: ubuntu-latest

    steps:
    - name: Checkout code
      uses: actions/checkout@v6

    - name: Build Docker image
      run: |
        echo "=== Build image on GitHub-hosted runner ==="
        docker build -t $IMAGE_NAME:ci .

    - name: Export Docker image tar
      run: |
        docker save $IMAGE_NAME:ci | gzip > /tmp/$REPOSITORY_NAME-image.tar.gz

    - name: Upload image artifact
      uses: actions/upload-artifact@v7
      with:
        name: $REPOSITORY_NAME-image
        path: /tmp/$REPOSITORY_NAME-image.tar.gz
        retention-days: 1

  push-image:
    if: github.event_name == 'push'
    needs: build-image
    runs-on: $RUNNER_NAME
    concurrency:
      group: harbor-publish-\${{ github.repository }}
      cancel-in-progress: false

    steps:
    - name: Download image artifact
      uses: actions/download-artifact@v8
      with:
        name: $REPOSITORY_NAME-image
        path: /tmp

    - name: Install crane (verified release)
      shell: bash
      run: |
        set -euo pipefail
        case "\$(uname -m)" in
          x86_64) ARCH=x86_64; SHA256=0ab7a1d6932a213aed964ce97666c3077fe691c8606413674a8b3e0b9ec4cda0 ;;
          aarch64) ARCH=arm64; SHA256=898c0cff975f898a33e8c4580bdafb0e7c02c7faa33374e946762f97c4ab7110 ;;
          *) echo "Unsupported architecture" >&2; exit 1 ;;
        esac
        mkdir -p "\$RUNNER_TEMP/crane-bin"
        curl --fail --silent --show-error --location \\
          "https://github.com/google/go-containerregistry/releases/download/v0.22.1/go-containerregistry_Linux_\$ARCH.tar.gz" \\
          -o "\$RUNNER_TEMP/crane.tar.gz"
        echo "\$SHA256  \$RUNNER_TEMP/crane.tar.gz" | sha256sum --check
        tar -xzf "\$RUNNER_TEMP/crane.tar.gz" -C "\$RUNNER_TEMP/crane-bin" crane

    - name: Push versioned image without Docker
      shell: bash
      run: |
        set -euo pipefail
        umask 077
        export DOCKER_CONFIG="\$RUNNER_TEMP/harbor-auth"
        mkdir -p "\$DOCKER_CONFIG"
        CRANE="\$RUNNER_TEMP/crane-bin/crane"
        HARBOR_URL=\$(cat /etc/harbor-auth/HARBOR_URL)
        HARBOR_PROJECT=\$(cat /etc/harbor-auth/HARBOR_PROJECT)
        HARBOR_USERNAME=\$(cat /etc/harbor-auth/HARBOR_USERNAME)
        "\$CRANE" auth login "\$HARBOR_URL" --username "\$HARBOR_USERNAME" \\
          --password-stdin < /etc/harbor-auth/HARBOR_PASSWORD
        gunzip -c /tmp/$REPOSITORY_NAME-image.tar.gz > "\$RUNNER_TEMP/image.tar"
        VERSION="build-\$GITHUB_RUN_ID-\$GITHUB_RUN_ATTEMPT-\$GITHUB_SHA"
        "\$CRANE" push "\$RUNNER_TEMP/image.tar" "\$HARBOR_URL/\$HARBOR_PROJECT/$IMAGE_NAME:\$VERSION"

    - name: Check publication is still the default branch head
      id: publication
      uses: actions/github-script@v7
      with:
        result-encoding: string
        script: |
          const {data: repo} = await github.rest.repos.get(context.repo);
          if (context.ref !== \`refs/heads/\${repo.default_branch}\`) return false;
          const {data: head} = await github.rest.repos.getCommit({...context.repo, ref: repo.default_branch});
          return head.sha === context.sha;

    - name: Promote current build to latest
      if: \${{ steps.publication.outputs.result == 'true' }}
      shell: bash
      run: |
        set -euo pipefail
        export DOCKER_CONFIG="\$RUNNER_TEMP/harbor-auth"
        HARBOR_URL=\$(cat /etc/harbor-auth/HARBOR_URL)
        HARBOR_PROJECT=\$(cat /etc/harbor-auth/HARBOR_PROJECT)
        VERSION="build-\$GITHUB_RUN_ID-\$GITHUB_RUN_ATTEMPT-\$GITHUB_SHA"
        "\$RUNNER_TEMP/crane-bin/crane" tag "\$HARBOR_URL/\$HARBOR_PROJECT/$IMAGE_NAME:\$VERSION" latest

    - name: Cleanup
      if: always()
      shell: bash
      run: |
        rm -rf "\$RUNNER_TEMP/harbor-auth" "\$RUNNER_TEMP/crane-bin"
        rm -f "\$RUNNER_TEMP/crane.tar.gz" "\$RUNNER_TEMP/image.tar" /tmp/$REPOSITORY_NAME-image.tar.gz
WORKFLOW_EOF

log_status "=== セットアップ完了 ==="
log_status ""
log_status "✅ Runner定義登録:"
log_status "   - $RUNNER_NAME (minRunners=$MIN_RUNNERS, maxRunners=$MAX_RUNNERS)"
log_status "   - strategy: latest"
log_status "   - リポジトリ: https://github.com/$GITHUB_USERNAME/$REPOSITORY_NAME"
log_status ""
log_status "✅ GitHub Actions workflow作成:"
log_status "   - $WORKFLOW_FILE"
log_status ""
log_status "📝 次のステップ:"
log_status "1. アプリリポジトリに workflow を反映して Commit & Push"
log_status "2. ArgoCD同期を確認（${RUNNER_SLUG}-runner等がSynced/Healthy）"
log_status "3. GitHub ActionsでCI/CDテスト実行"
log_status ""
log_status "🎉 $REPOSITORY_NAME 用のRunner環境が準備完了しました！"
