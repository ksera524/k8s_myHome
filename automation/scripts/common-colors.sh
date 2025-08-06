#!/bin/bash

# 共通カラー定義スクリプト
# Makefileの設定に合わせてカラーは無効化

# カラー定義（無効化 - 実行環境の制約により）
GREEN=""
YELLOW=""
RED=""
BLUE=""
NC=""

# print関数定義（絵文字ベース）
print_status() {
    echo "ℹ️  $1"
}

print_warning() {
    echo "⚠️  $1"
}

print_error() {
    echo "❌ $1"
}

print_debug() {
    echo "🔍 $1"
}

print_success() {
    echo "✅ $1"
}

# 関数をエクスポート
export -f print_status
export -f print_warning
export -f print_error
export -f print_debug
export -f print_success

# カラー変数をエクスポート
export GREEN
export YELLOW
export RED
export BLUE
export NC