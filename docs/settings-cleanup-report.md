# settings.toml 設定整理レポート

## 📋 調査結果

### 実際に使用されている設定

| セクション | キー | 使用箇所 | 用途 |
|-----------|------|----------|------|
| `[host_setup]` | `usb_device_name` | `setup-storage.sh`, `settings-loader.sh` | USB外部ストレージデバイス名の自動入力 |
| `[pulumi]` | `access_token` | `platform-deploy.sh`, `eso-fix.sh`, `setup-eso-prerequisites.sh` | External Secrets Operator用のPulumi Access Token |
| `[github]` | `username` | `add-runner.sh`, `add-runner-argocd.sh`, `platform-deploy.sh` | GitHub Actions Runner作成時のリポジトリURL生成 |
| `[github]` | `arc_repositories` | `platform-deploy.sh` (Line 605-693) | make all時の自動Runner追加 |
| `[automation]` | `auto_confirm_overwrite` | `settings-loader.sh` | 確認プロンプトの自動応答 |

### 削除した未使用設定

| セクション | キー | 削除理由 |
|-----------|------|----------|
| `[kubernetes]` | `overwrite_kubernetes_keyring` | コード内で使用されていない（検索結果: settings-loader.shのexpectスクリプト内のみ） |
| `[github]` | `personal_access_token` | GITHUB_TOKENはExternal Secrets経由で取得（実際の利用なし） |
| `[github]` | `repository` | 実際のコードで使用されていない |
| `[network]` | 全項目 | ネットワーク設定はコード内でハードコードされており、settings.tomlから読み込まれていない |
| `[automation]` | `enable_external_secrets` | コード内で参照されていない |
| `[automation]` | `enable_github_actions` | コード内で参照されていない |
| `[logging]` | `debug` | コード内で参照されていない |
| `[logging]` | `verbose` | コード内で参照されていない |

## 🔍 詳細分析

### 1. ネットワーク設定の現状
- IPアドレスやポート番号は全てスクリプト内にハードコードされている
- `settings-loader.sh`でネットワーク設定の環境変数エクスポート処理があるが、実際には使用されていない
- 例: `platform-deploy.sh`では `192.168.122.10` が直接記述されている

### 2. GitHub Personal Access Token
- `settings-loader.sh`で`GITHUB_PERSONAL_ACCESS_TOKEN`を`GITHUB_TOKEN`にマッピングする処理はある
- しかし、実際のGitHub認証はExternal Secrets Operator経由で取得している
- `github-auth-utils.sh`でExternal Secretsから取得する処理が実装済み

### 3. 自動化オプション
- `auto_confirm_overwrite`のみが実際に使用されている
- 他の`enable_*`オプションは定義されているが参照されていない

## ✅ 改善後の設定ファイル構造

```toml
# 最小限の必要設定のみ
[host_setup]
usb_device_name = ""  # USB外部ストレージ設定時のみ

[pulumi]  
access_token = ""  # External Secrets Operator用（必須）

[github]
username = ""  # GitHub Actions Runner用（必須）
arc_repositories = []  # 自動Runner追加用

[automation]
auto_confirm_overwrite = true  # プロンプト自動応答
```

## 🚀 今後の推奨事項

### 1. ネットワーク設定の活用
現在ハードコードされているネットワーク設定を`settings.toml`から読み込むよう改修することで、環境ごとの設定変更が容易になる。

### 2. 設定の一元化
`settings.toml`に全ての設定を集約し、スクリプト内のハードコード値を削減する。

### 3. 環境変数マッピングの整理
`settings-loader.sh`で定義されているが使用されていない環境変数マッピングを削除または活用する。

---

作成日: 2025-01-26
調査方法: grep, mcp__serena__search_for_pattern による全コードベース検索