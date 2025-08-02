# コードスタイルとコンベンション

## 言語とコメント
- **コメント**: 必ず日本語で記述
- **応答**: 必ず日本語で応答
- **ドキュメント**: 日本語を基本とし、必要に応じて英語併記

## ディレクトリ構造
- **manifests/**: Kubernetesマニフェスト管理（infra配下は使用しない）
- **automation/**: 自動化スクリプト群
  - **host-setup/**: ホスト準備
  - **infrastructure/**: インフラ構築
  - **platform/**: プラットフォームサービス

## シェルスクリプト規約
- `set -euo pipefail` で厳密エラーハンドリング
- 色付きログ出力（RED, GREEN, YELLOW, BLUE）
- `print_status()`, `print_warning()`, `print_error()`, `print_debug()` 関数の使用
- SSH接続時の `-o StrictHostKeyChecking=no` オプション使用

## Kubernetes リソース命名
- namespace: kebab-case（例：`arc-systems`, `external-secrets-system`）
- secrets: 用途別命名（例：`harbor-auth`, `github-token`, `pulumi-access-token`）
- 日本語コメントでリソース説明追加

## GitOps管理
- App-of-Apps パターンでArgoCD管理
- `manifests/app-of-apps.yaml` が最上位管理ファイル
- External Secrets Operator で秘密情報管理を優先