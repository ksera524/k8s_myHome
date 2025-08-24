# スクリプトリファクタリングガイド

## 概要
このガイドでは、k8s_myHomeプロジェクトの自動化スクリプトのリファクタリング内容と使用方法を説明します。

## 新しい共通ライブラリ

### 1. common-ssh.sh
SSH接続の重複コードを削減するための共通関数。

```bash
# 使用例
source automation/scripts/common-ssh.sh

# コントロールプレーンでコマンド実行
k8s_ssh_control "kubectl get nodes"

# 全ノードでコマンド実行
k8s_ssh_all_nodes "sudo systemctl status kubelet"

# kubectl実行（簡易版）
k8s_kubectl "get pods --all-namespaces"
```

### 2. common-sudo.sh
sudo操作を簡素化する共通関数。

```bash
# 使用例
source automation/scripts/common-sudo.sh

# ディレクトリ作成と権限設定
create_directory "/opt/myapp" "myuser:mygroup" "755"

# サービス管理
manage_service restart nginx

# パッケージインストール
install_packages git curl wget
```

### 3. common-validation.sh
各種検証処理を統一化。

```bash
# 使用例
source automation/scripts/common-validation.sh

# 前提条件チェック
check_network_connectivity
check_disk_space "/" 50  # 50GB必要
check_memory 8          # 8GB必要
check_kubectl_config
```

### 4. sudo-manager.sh
改善されたsudo権限管理。

```bash
# 使用例
source automation/scripts/sudo-manager.sh

# スクリプト開始時
acquire_sudo
maintain_sudo
setup_sudo_trap  # 自動クリーンアップ

# コマンド実行
sudo_exec "apt-get update"

# スクリプト終了時（trapで自動実行）
cleanup_sudo
```

### 5. common-error-handler.sh
統一されたエラーハンドリング。

```bash
# 使用例
source automation/scripts/common-error-handler.sh

# エラーハンドラー初期化
init_error_handler

# リトライ機能
retry_command 3 10 kubectl apply -f manifest.yaml

# タイムアウト機能
timeout_command 300 ./long-running-script.sh

# プログレス表示
for i in {1..100}; do
    show_progress $i 100 "Processing files"
    sleep 0.1
done
```

## リファクタリングされたスクリプト例

### platform-deploy-refactored.sh
新しい共通関数を使用した実装例。

主な改善点：
- SSH接続の共通化（97回の重複を削減）
- エラーハンドリングの統一
- 関数による構造化
- 設定の一元管理

## 依存関係管理

`scripts/dependencies.toml`で各スクリプトの依存関係を定義：

```toml
[scripts.platform-deploy]
description = "プラットフォームデプロイ"
dependencies = ["common-colors", "common-ssh", "common-k8s-utils", "settings-loader"]
phase = "platform"
order = 1
```

## 移行ガイド

### 既存スクリプトの更新方法

1. **共通関数の読み込み**
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/common-ssh.sh"
source "$SCRIPT_DIR/../scripts/common-sudo.sh"
source "$SCRIPT_DIR/../scripts/common-validation.sh"
```

2. **SSH接続の置き換え**
```bash
# 旧：
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 "kubectl get nodes"

# 新：
k8s_ssh_control "kubectl get nodes"
```

3. **sudo操作の置き換え**
```bash
# 旧：
sudo -n mkdir -p /opt/app
sudo -n chown -R user:group /opt/app
sudo -n chmod 755 /opt/app

# 新：
create_directory "/opt/app" "user:group" "755"
```

4. **エラーハンドリングの改善**
```bash
# スクリプト開始時
init_error_handler

# クリーンアップ関数定義
cleanup_on_error() {
    print_warning "エラー発生時のクリーンアップ処理"
    # 必要なクリーンアップ処理
}
```

## ベストプラクティス

1. **設定の外部化**
   - `config/`ディレクトリの設定ファイルを使用
   - 環境変数による設定のオーバーライド

2. **エラー処理**
   - `set -euo pipefail`を常に使用
   - `init_error_handler`でエラートラップ設定
   - 重要な操作には`retry_command`を使用

3. **ログ記録**
   - `print_status`、`print_error`等を使用
   - エラーログは自動的に記録される

4. **テスト容易性**
   - 関数を小さく保つ
   - 副作用を最小限に
   - モック可能な設計

## 今後の改善予定

1. **ユニットテスト追加**
   - batsフレームワークの導入
   - 各共通関数のテスト作成

2. **CI/CD統合**
   - シェルスクリプトの構文チェック
   - 依存関係の自動検証

3. **ドキュメント自動生成**
   - 関数のドキュメントから自動生成
   - 使用例の自動抽出