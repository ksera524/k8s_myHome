#!/bin/bash

# GitHub認証情報管理用ユーティリティ関数

# 設定ファイルのパス
GITHUB_CONFIG_FILE="$HOME/.k8s_myhome_github_config"

# GitHub認証情報を保存する関数
save_github_credentials() {
    local username="$1"
    local token="$2"
    
    if [[ -z "$username" || -z "$token" ]]; then
        echo "エラー: ユーザー名とトークンの両方が必要です"
        return 1
    fi
    
    # ファイルに保存（権限を厳しく設定）
    cat > "$GITHUB_CONFIG_FILE" << EOF
GITHUB_USERNAME="$username"
GITHUB_TOKEN="$token"
EOF
    
    # ファイル権限を所有者のみ読み書き可能に設定
    chmod 600 "$GITHUB_CONFIG_FILE"
    
    echo "GitHub認証情報を保存しました: $GITHUB_CONFIG_FILE"
}

# GitHub認証情報を読み込む関数
load_github_credentials() {
    if [[ -f "$GITHUB_CONFIG_FILE" ]]; then
        source "$GITHUB_CONFIG_FILE"
        if [[ -n "${GITHUB_USERNAME:-}" && -n "${GITHUB_TOKEN:-}" ]]; then
            echo "保存済みのGitHub認証情報を読み込みました"
            return 0
        fi
    fi
    return 1
}

# GitHub認証情報をチェック・取得する関数
get_github_credentials() {
    # 既に環境変数が設定されている場合はそれを使用
    if [[ -n "${GITHUB_USERNAME:-}" && -n "${GITHUB_TOKEN:-}" ]]; then
        echo "環境変数からGitHub認証情報を使用します"
        return 0
    fi
    
    # External Secretsから取得を試行（k8sクラスタに接続可能な場合）
    if command -v kubectl >/dev/null 2>&1 && ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 k8suser@192.168.122.10 'kubectl version --client' >/dev/null 2>&1; then
        if ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret github-auth -n arc-systems' >/dev/null 2>&1; then
            echo "External SecretsからGitHub認証情報を取得中..."
            
            GITHUB_TOKEN_ES=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret github-auth -n arc-systems -o jsonpath="{.data.GITHUB_TOKEN}" | base64 -d' 2>/dev/null || echo "")
            GITHUB_USERNAME_ES=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret github-auth -n arc-systems -o jsonpath="{.data.GITHUB_USERNAME}" | base64 -d' 2>/dev/null || echo "")
            
            if [[ -n "$GITHUB_TOKEN_ES" && -n "$GITHUB_USERNAME_ES" && "$GITHUB_TOKEN_ES" != "" && "$GITHUB_USERNAME_ES" != "" ]]; then
                echo "✓ External SecretsからGitHub認証情報を取得しました"
                echo "ユーザー名: $GITHUB_USERNAME_ES"
                echo "トークン: ${GITHUB_TOKEN_ES:0:8}... (先頭8文字のみ表示)"
                
                export GITHUB_USERNAME="$GITHUB_USERNAME_ES"
                export GITHUB_TOKEN="$GITHUB_TOKEN_ES"
                return 0
            else
                echo "⚠️ External SecretsからGitHub認証情報の取得に失敗しました"
                echo "Pulumi ESCにgithub/github_usernameキーが存在しない可能性があります"
            fi
        fi
    fi
    
    # 保存済み認証情報を読み込み試行
    if load_github_credentials; then
        echo "ユーザー名: ${GITHUB_USERNAME:-}"
        echo "トークン: ${GITHUB_TOKEN:0:8}... (先頭8文字のみ表示)"
        
        # 確認プロンプト
        read -p "保存済みのGitHub認証情報を使用しますか？ (y/n) [y]: " -r use_saved
        use_saved=${use_saved:-y}
        
        if [[ "$use_saved" =~ ^[Yy]$ ]]; then
            export GITHUB_USERNAME
            export GITHUB_TOKEN
            return 0
        fi
    fi
    
    # 新しい認証情報を入力
    echo ""
    echo "=== GitHub認証情報の入力 ==="
    read -p "GitHubユーザー名を入力してください: " GITHUB_USERNAME
    if [[ -z "${GITHUB_USERNAME:-}" ]]; then
        echo "エラー: GitHubユーザー名は必須です"
        return 1
    fi
    
    read -s -p "GitHubトークンを入力してください: " GITHUB_TOKEN
    echo ""
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        echo "エラー: GitHubトークンは必須です"
        return 1
    fi
    
    # 認証情報を保存するか確認
    read -p "この認証情報を保存しますか？ (y/n) [y]: " -r save_creds
    save_creds=${save_creds:-y}
    
    if [[ "$save_creds" =~ ^[Yy]$ ]]; then
        save_github_credentials "$GITHUB_USERNAME" "$GITHUB_TOKEN"
    fi
    
    export GITHUB_USERNAME
    export GITHUB_TOKEN
    return 0
}

# 保存済み認証情報を削除する関数
clear_github_credentials() {
    if [[ -f "$GITHUB_CONFIG_FILE" ]]; then
        rm -f "$GITHUB_CONFIG_FILE"
        echo "保存済みGitHub認証情報を削除しました"
    else
        echo "保存済みGitHub認証情報は見つかりませんでした"
    fi
}

# 保存済み認証情報の状態を表示する関数
show_github_credentials_status() {
    if [[ -f "$GITHUB_CONFIG_FILE" ]]; then
        if load_github_credentials; then
            echo "✅ GitHub認証情報が保存されています"
            echo "   ユーザー名: ${GITHUB_USERNAME:-}"
            echo "   トークン: ${GITHUB_TOKEN:0:8}... (先頭8文字のみ表示)"
        else
            echo "⚠️  設定ファイルは存在しますが、認証情報が不完全です"
        fi
    else
        echo "❌ GitHub認証情報は保存されていません"
    fi
}