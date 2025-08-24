# k8s_myHome ドキュメント

## ドキュメント構成

### [アーキテクチャ](architecture/)
- [システム概要](architecture/overview.md) - 全体構成とコンポーネント
- [ネットワーク設計](architecture/network.md) - ネットワーク構成詳細
- [アーキテクチャ図](architecture/diagrams/) - システム構成図

### [運用ガイド](operations/)
- [デプロイメント手順](operations/deployment.md) - 環境構築手順
- [メンテナンス手順](operations/maintenance.md) - 日常運用タスク
- [バックアップ手順](operations/backup.md) - バックアップとリストア

### [トラブルシューティング](troubleshooting/)
- [よくある問題](troubleshooting/common-issues.md) - 一般的な問題と解決方法
- [デバッグガイド](troubleshooting/debug-guide.md) - 詳細なデバッグ手順
- [FAQ](troubleshooting/faq.md) - よくある質問

### [開発ガイド](development/)
- [開発環境構築](development/setup.md) - 開発環境のセットアップ
- [コントリビューション](development/contributing.md) - 貢献方法

## クイックリンク

### 初めての方へ
1. [CLAUDE.md](../CLAUDE.md) - プロジェクト概要
2. [デプロイメント手順](operations/deployment.md) - 環境構築
3. [よくある問題](troubleshooting/common-issues.md) - トラブルシューティング

### 管理者向け
- [設定リファレンス](../config/) - 設定ファイル詳細
- [Makefile ヘルプ](../Makefile) - 自動化コマンド一覧
- [settings.toml](../automation/settings.toml) - 自動化設定

## 更新履歴
- 2025-01-24: ドキュメント構造の再編成
- 2025-01-23: Terraform-Ansible統合完了
- 2025-01-20: 初期リリース