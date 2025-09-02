#!/bin/bash

# libvirt関連コマンドのsudo権限設定スクリプト
# make allを実行するユーザーがパスワードなしでlibvirt関連コマンドを実行できるようにする

set -e

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}ℹ️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# ユーザー名取得
CURRENT_USER="${USER:-$(whoami)}"

print_status "libvirt sudo権限設定を開始します"
print_status "設定対象ユーザー: $CURRENT_USER"

# sudoersファイル作成
SUDOERS_FILE="/etc/sudoers.d/50-libvirt-nopasswd"
TEMP_FILE="/tmp/50-libvirt-nopasswd.tmp"

print_status "sudoers設定ファイルを作成中..."

cat << EOF > "$TEMP_FILE"
# libvirt関連コマンドのパスワードなし実行許可
# Created by setup-libvirt-sudo.sh

# virshコマンド群
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/virsh *
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/virt-install *
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/virt-clone *
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/virt-xml *

# systemctl（libvirt関連のみ）
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl start libvirtd
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop libvirtd
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart libvirtd
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl status libvirtd
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl start virtlogd
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop virtlogd
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart virtlogd

# ファイル操作（libvirt関連ディレクトリのみ）
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/chown -R libvirt-qemu\:kvm /var/lib/libvirt/images/
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/find /var/lib/libvirt/images/ *
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/chmod * /var/lib/libvirt/images/*
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/rm -rf /var/lib/libvirt/images/*

# ブリッジ関連
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/sbin/brctl *
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/sbin/ip *

# journalctl（libvirt関連ログのみ）
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/journalctl -u libvirtd *
EOF

# visudoで文法チェック
if sudo visudo -c -f "$TEMP_FILE"; then
    print_status "sudoers設定の文法チェック完了"
    # sudoersディレクトリにコピー
    sudo cp "$TEMP_FILE" "$SUDOERS_FILE"
    sudo chmod 440 "$SUDOERS_FILE"
    print_status "✓ sudoers設定ファイルをインストールしました: $SUDOERS_FILE"
else
    print_error "sudoers設定の文法エラーが検出されました"
    rm -f "$TEMP_FILE"
    exit 1
fi

# 一時ファイル削除
rm -f "$TEMP_FILE"

# libvirtグループ確認と追加
if ! groups "$CURRENT_USER" | grep -q libvirt; then
    print_warning "ユーザー $CURRENT_USER をlibvirtグループに追加します"
    sudo usermod -aG libvirt "$CURRENT_USER"
    print_warning "グループの変更を反映するには、一度ログアウトして再ログインが必要です"
fi

# テスト実行
print_status "設定をテスト中..."
if sudo -n virsh list --all >/dev/null 2>&1; then
    print_status "✓ virshコマンドのパスワードなし実行: OK"
else
    print_warning "virshコマンドのテスト失敗（再ログインが必要な可能性があります）"
fi

print_status "=== libvirt sudo権限設定完了 ==="
print_status ""
print_status "次のステップ:"
print_status "1. 一度ログアウトして再ログインしてください（グループ変更の反映）"
print_status "2. make all を実行してください"
print_status ""
print_status "設定を元に戻す場合:"
print_status "  sudo rm $SUDOERS_FILE"