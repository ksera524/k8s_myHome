#!/bin/bash
# Helmリポジトリエラーを修正するスクリプト

echo "======================================"
echo "Fixing Helm repository issue..."
echo "======================================"
echo ""
echo "This script needs sudo privileges."
echo ""

# 壊れたHelmリポジトリを削除
if [ -f /etc/apt/sources.list.d/helm-stable-debian.list ]; then
    echo "[1] Removing old Helm repository configuration..."
    sudo rm -f /etc/apt/sources.list.d/helm-stable-debian.list
    echo "    ✓ Removed /etc/apt/sources.list.d/helm-stable-debian.list"
else
    echo "[1] No Helm repository file found (already removed)"
fi

if [ -f /usr/share/keyrings/helm.gpg ]; then
    echo "[2] Removing old Helm GPG key..."
    sudo rm -f /usr/share/keyrings/helm.gpg
    echo "    ✓ Removed /usr/share/keyrings/helm.gpg"
else
    echo "[2] No Helm GPG key found (already removed)"
fi

# apt updateを実行してリポジトリリストをクリーン
echo ""
echo "[3] Updating package lists to verify fix..."
if sudo apt-get update 2>&1 | grep -q "403.*helm"; then
    echo "    ⚠️  Warning: Helm repository error still detected"
    echo "    Trying additional cleanup..."
    
    # apt cacheもクリア
    sudo apt-get clean
    sudo rm -rf /var/lib/apt/lists/*
    echo "    ✓ Cleared apt cache"
    
    echo "    Updating package lists again..."
    sudo apt-get update
else
    echo "    ✓ Package lists updated successfully"
fi

echo ""
echo "======================================"
echo "✅ Helm repository issue should be fixed!"
echo "======================================"
echo ""
echo "You can now run 'make all' again."
echo ""
echo "If the problem persists, try:"
echo "  sudo apt-get clean"
echo "  sudo rm -rf /var/lib/apt/lists/*"
echo "  sudo apt-get update"