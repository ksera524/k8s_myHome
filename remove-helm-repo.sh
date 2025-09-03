#!/bin/bash
# Helmリポジトリファイルを強制削除

set -e

echo "==============================================="
echo " Helm Repository 403 Error Fix"
echo "==============================================="
echo ""

# sudo権限の確認
if [ "$EUID" -ne 0 ]; then 
    echo "このスクリプトはsudo権限が必要です。"
    echo "実行コマンド: sudo bash $0"
    echo ""
    echo "または、以下のコマンドを手動で実行してください:"
    echo ""
    echo "sudo rm -f /etc/apt/sources.list.d/helm-stable-debian.list"
    echo "sudo rm -f /usr/share/keyrings/helm.gpg"
    echo ""
    exit 1
fi

echo "[STEP 1] 問題のあるHelmリポジトリファイルを削除..."
if [ -f /etc/apt/sources.list.d/helm-stable-debian.list ]; then
    rm -f /etc/apt/sources.list.d/helm-stable-debian.list
    echo "  ✓ /etc/apt/sources.list.d/helm-stable-debian.list を削除しました"
else
    echo "  - ファイルが見つかりません (既に削除済み？)"
fi

echo ""
echo "[STEP 2] Helm GPGキーを削除..."
if [ -f /usr/share/keyrings/helm.gpg ]; then
    rm -f /usr/share/keyrings/helm.gpg
    echo "  ✓ /usr/share/keyrings/helm.gpg を削除しました"
else
    echo "  - GPGキーが見つかりません (既に削除済み？)"
fi

echo ""
echo "[STEP 3] APTキャッシュをクリア..."
apt-get clean
echo "  ✓ APTキャッシュをクリアしました"

echo ""
echo "[STEP 4] APTリストを再構築..."
rm -rf /var/lib/apt/lists/*
echo "  ✓ APTリストを削除しました"

echo ""
echo "[STEP 5] パッケージリストを更新..."
echo ""
apt-get update

echo ""
echo "==============================================="
echo " ✅ 修正完了！"
echo "==============================================="
echo ""
echo "make all を再実行できます。"