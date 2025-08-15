# settings.toml 設定ファイル

make all実行時の標準入力要求を自動化するための設定ファイルです。

## 概要

`make all`を実行すると、通常以下のような標準入力が要求されます：
- USB外部ストレージデバイス名の入力
- Kubernetes APT鍵ファイル上書き確認
- Pulumi Access Token入力
- GitHub Personal Access Token入力
- 各種確認プロンプト

`settings.toml`を使用することで、これらの入力を事前に設定し、完全自動化することができます。

## セットアップ

### 1. 設定ファイル作成

```bash
cd automation
cp settings.toml.example settings.toml  # または手動で作成
```

### 2. 設定値の入力

`settings.toml`を編集して、適切な値を設定してください：

```toml
[host_setup]
# lsblk で確認したUSBデバイス名
usb_device_name = "sdc"

[pulumi]
# https://app.pulumi.com/account/tokens で取得
access_token = "${PULUMI_ACCESS_TOKEN}"  # 環境変数で設定


[github]
# GitHub Settings > Developer settings > Personal access tokens で取得
personal_access_token = "${GITHUB_TOKEN}"  # 環境変数またはESO経由で設定
repository = "ksera524/k8s_myHome"
username = "ksera524"

[automation]
# 確認プロンプトを自動でYesにする
auto_confirm_overwrite = true
```

### 3. make all実行

設定ファイルが存在する場合、自動的に読み込まれます：

```bash
make all
```

## 設定項目詳細

### [host_setup]
- `usb_device_name`: 外部ストレージのデバイス名（例: sdb, sdc, nvme0n1）
  - `lsblk`コマンドで確認可能

### [kubernetes]
- `overwrite_kubernetes_keyring`: Kubernetes APT鍵ファイル上書き確認（通常は "y"）

### [pulumi]
- `access_token`: Pulumi Access Token（External Secrets Operator用）
  - 取得方法: https://app.pulumi.com/account/tokens
  - 形式: `pul-` で始まる40文字の英数字

**注記**: CloudflaredのトークンはExternal Secrets Operatorを通じてPulumi ESCから自動取得されるため、個別設定は不要です。


### [github]
- `personal_access_token`: GitHub Personal Access Token
  - Actions Runner Controller用
  - 権限: `repo`, `workflow`, `admin:org` (組織使用時)
- `repository`: GitHub Repository（例: username/repository）
- `username`: GitHubユーザー名（ArgoCD OAuth用）

### [harbor]
- `admin_password`: Harbor管理者パスワード（ESO経由で管理）
- `url`: Harbor URL（デフォルト: http://192.168.122.100）
- `project`: Harbor Project名（デフォルト: library）

### [automation]
- `auto_confirm_overwrite`: 確認プロンプトを自動でYesにする
- `enable_external_secrets`: External Secretsを有効にする
- `enable_github_actions`: GitHub Actionsセットアップを有効にする

## セキュリティ注意事項

⚠️ **重要**: `settings.toml`には機密情報が含まれます

- ファイルは自動的に`.gitignore`に追加されます
- リポジトリにコミットしないでください
- 適切なファイル権限を設定してください：
  ```bash
  chmod 600 automation/settings.toml
  ```

## トラブルシューティング

### 設定ファイルが読み込まれない
- `automation/settings.toml`が正しい場所にあるか確認
- ファイルの構文エラーがないかチェック
- TOMLフォーマットが正しいか確認

### 一部の設定が反映されない
- キー名や値の形式が正しいか確認
- 文字列値は必ず `"` で囲む
- ブール値は `true`/`false`（クォートなし）

### 標準入力が要求される
- 対応する設定項目が空でないか確認
- スクリプトが対応していない入力である可能性

## 高度な使用方法

### 環境変数での実行
設定ファイルの代わりに環境変数を使用することも可能：

```bash
export PULUMI_ACCESS_TOKEN="pul-xxxxxxxx..."
export GITHUB_TOKEN="ghp-xxxxxxxx..."
make all
```

### 部分的な自動化
一部の項目のみ設定して、他は手動入力することも可能：

```toml
[pulumi]
access_token = "pul-xxxxxxxx..."

# 他の項目は空のまま（手動入力になる）
```

### デバッグモード
詳細ログを有効にする：

```toml
[logging]
debug = true
verbose = true
```

## 関連ファイル

- `automation/scripts/settings-loader.sh`: 設定読み込みスクリプト
- `automation/Makefile`: make allでの自動読み込み設定
- `.gitignore`: settings.tomlの除外設定