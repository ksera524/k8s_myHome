#!/bin/bash
# sudo keepaliveプロセスをクリーンアップ

# 色設定
source "$(dirname "$0")/common-colors.sh" 2>/dev/null || true

# PIDファイルから読み取り
if [ -f /tmp/sudo_keepalive.pid ]; then
    KEEPALIVE_PID=$(cat /tmp/sudo_keepalive.pid)
    
    # プロセスが存在するか確認
    if ps -p $KEEPALIVE_PID > /dev/null 2>&1; then
        kill $KEEPALIVE_PID 2>/dev/null
        echo "✅ sudo権限維持プロセスを停止しました (PID: $KEEPALIVE_PID)"
    else
        echo "ℹ️  sudo権限維持プロセスは既に停止しています"
    fi
    
    # PIDファイルを削除
    rm -f /tmp/sudo_keepalive.pid
else
    echo "ℹ️  sudo権限維持プロセスは実行されていません"
fi

# 念のため、すべてのsudo_keepaliveプロセスを停止
pkill -f "sudo_keepalive" 2>/dev/null || true