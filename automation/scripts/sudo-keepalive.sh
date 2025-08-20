#!/bin/bash
# sudo権限を維持するためのバックグラウンドプロセス
# make all実行中、sudoパスワードの再入力を防ぐ

# 色設定
source "$(dirname "$0")/common-colors.sh" 2>/dev/null || true

# バックグラウンドでsudo権限を更新し続ける
sudo_keepalive() {
    while true; do
        sudo -n true 2>/dev/null
        sleep 50
    done
}

# 既存のkeepaliveプロセスを確認
if pgrep -f "sudo_keepalive" > /dev/null 2>&1; then
    echo "⚠️ sudo keepaliveプロセスは既に実行中です"
    exit 0
fi

# sudo権限を初期取得
echo "🔐 make all実行のためsudo権限が必要です（パスワードは最初の1回のみ）"
if ! sudo -v; then
    echo "❌ sudo権限の取得に失敗しました"
    exit 1
fi

# バックグラウンドでkeepaliveを開始
sudo_keepalive &
KEEPALIVE_PID=$!

# プロセスIDを保存
echo $KEEPALIVE_PID > /tmp/sudo_keepalive.pid

echo "✅ sudo権限維持プロセスを開始しました (PID: $KEEPALIVE_PID)"
echo "ℹ️  make all完了後、自動的に停止します"