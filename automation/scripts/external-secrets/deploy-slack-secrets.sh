#!/bin/bash

# External Secrets を使用したSlack認証情報デプロイスクリプト
# Harbor認証情報デプロイの実装を参考に作成

set -euo pipefail

# スクリプトディレクトリ取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 共通色設定スクリプトを読み込み
source "$SCRIPT_DIR/../common-colors.sh"

print_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

print_status "=== External Secrets による Slack 認証情報デプロイ ==="

# 前提条件確認
print_status "前提条件を確認中..."

# External Secrets Operator が稼働中かチェック
ESO_DEPLOYMENTS=$(kubectl get deployments -n external-secrets-system --no-headers 2>/dev/null | grep -E "(external-secrets)" | wc -l || echo "0")
if [ "$ESO_DEPLOYMENTS" = "0" ]; then
    print_error "External Secrets Operator が見つかりません"
    print_error "先に setup-external-secrets.sh を実行してください"
    exit 1
fi

print_debug "✓ External Secrets Operator 稼働確認完了"

# Pulumi Access Token が設定済みかチェック
if ! kubectl get secret pulumi-access-token -n external-secrets-system >/dev/null 2>&1; then
    print_error "Pulumi Access Token が設定されていません"
    print_error "以下のいずれかの方法で設定してください："
    print_error "1. ./setup-pulumi-pat.sh --interactive"
    print_error "2. export PULUMI_ACCESS_TOKEN=\"pul-xxx...\" && echo \"\$PULUMI_ACCESS_TOKEN\" | ./setup-pulumi-pat.sh"
    exit 1
fi

print_debug "✓ Pulumi Access Token 設定確認完了"

# ClusterSecretStore が設定済みかチェック
if ! kubectl get clustersecretstore pulumi-esc-store >/dev/null 2>&1; then
    print_error "ClusterSecretStore 'pulumi-esc-store' が見つかりません"
    print_error "先に Harbor ExternalSecrets を設定してください："
    print_error "./deploy-harbor-secrets.sh"
    exit 1
fi

print_debug "✓ ClusterSecretStore 設定確認完了"

# ClusterSecretStore 接続確認
print_debug "ClusterSecretStore 接続確認中..."
SECRETSTORE_STATUS=$(kubectl get clustersecretstore pulumi-esc-store -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
if [ "$SECRETSTORE_STATUS" != "True" ]; then
    print_error "ClusterSecretStore が準備できていません (Status: $SECRETSTORE_STATUS)"
    if [ "$SECRETSTORE_STATUS" = "False" ]; then
        ERROR_MESSAGE=$(kubectl get clustersecretstore pulumi-esc-store -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "Unknown")
        print_error "接続エラー詳細: $ERROR_MESSAGE"
    fi
    print_error "先に Harbor ExternalSecrets を正常に設定してください"
    exit 1
fi

print_debug "✓ ClusterSecretStore 接続確認完了"

# sandbox ネームスペース作成確認
print_status "sandbox ネームスペースを確認中..."
if ! kubectl get namespace sandbox >/dev/null 2>&1; then
    print_debug "ネームスペース sandbox を作成中..."
    kubectl create namespace sandbox
    print_status "✓ ネームスペース sandbox を作成"
else
    print_debug "✓ ネームスペース sandbox は既に存在"
fi

# Slack ExternalSecret の適用
print_status "Slack ExternalSecret を適用中..."

# ExternalSecret YAML を適用
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/externalsecrets/slack-externalsecret.yaml" ]; then
    kubectl apply -f "$SCRIPT_DIR/externalsecrets/slack-externalsecret.yaml"
    print_status "✓ Slack ExternalSecret を適用しました"
else
    print_error "slack-externalsecret.yaml が見つかりません"
    print_error "パス: $SCRIPT_DIR/externalsecrets/slack-externalsecret.yaml"
    exit 1
fi

# ExternalSecret の同期を待機
print_status "Slack Secret の同期を待機中..."

print_debug "slack secret の同期待機中..."
timeout=120
while [ $timeout -gt 0 ]; do
    if kubectl get secret slack -n sandbox >/dev/null 2>&1; then
        print_status "✓ slack secret 同期完了"
        break
    fi
    
    # ExternalSecret の状態確認
    EXTERNALSECRET_STATUS=$(kubectl get externalsecret slack-externalsecret -n sandbox -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    if [ "$EXTERNALSECRET_STATUS" = "False" ]; then
        ERROR_MESSAGE=$(kubectl get externalsecret slack-externalsecret -n sandbox -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "Unknown")
        print_warning "ExternalSecret エラー: $ERROR_MESSAGE"
    fi
    
    echo "Slack secret 同期待機中... (残り ${timeout}秒) - Status: $EXTERNALSECRET_STATUS"
    sleep 5
    timeout=$((timeout - 5))
done

if [ $timeout -le 0 ]; then
    print_error "slack secret の同期がタイムアウトしました"
    print_warning "Pulumi ESCにslackキーが存在しない可能性があります"
    print_debug "詳細確認: kubectl describe externalsecret slack-externalsecret -n sandbox"
    print_warning "Pulumi ESC環境にslack secretが設定されているか確認してください"
    exit 1
fi

print_status "=== Slack 認証情報デプロイ完了 ==="

# 作成結果の確認
print_status "作成されたSecretの確認:"
echo "  Slack Secret:"
if kubectl get secret slack -n sandbox >/dev/null 2>&1; then
    echo "    ✓ sandbox: slack"
    
    # Secretの内容確認（キーのみ表示）
    print_debug "Secret キー一覧:"
    SECRET_KEYS=$(kubectl get secret slack -n sandbox -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null || echo "取得失敗")
    if [ "$SECRET_KEYS" != "取得失敗" ]; then
        echo "$SECRET_KEYS" | while read -r key; do
            echo "      - $key"
        done
    fi
else
    echo "    ❌ sandbox: slack (作成失敗)"
fi

echo ""
print_status "使用方法:"
echo "  Pod/Deployment で以下のように使用:"
echo "  env:"
echo "  - name: SLACK_WEBHOOK_URL"
echo "    valueFrom:"
echo "      secretKeyRef:"
echo "        name: slack"
echo "        key: webhook_url"
echo ""
print_status "確認コマンド:"
echo "  kubectl get externalsecret slack-externalsecret -n sandbox"
echo "  kubectl describe externalsecret slack-externalsecret -n sandbox"
echo "  kubectl get secret slack -n sandbox"