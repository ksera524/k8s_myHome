# k8s_myHome
おうちk8sクラスタの管理リポジトリ

## 構成図

- [App-of-Apps / Sync Wave 図](docs/diagrams/app-of-apps-sync-wave.md)

## 目的

このリポジトリは、ホームラボ向け Kubernetes クラスタの構築と運用を GitOps で管理するための構成・自動化・ドキュメントをまとめたものです。

## クイックスタート

```bash
# 1. 設定ファイル準備
cp automation/settings.toml.example automation/settings.toml

# 2. 全フェーズ実行
make all

# 3. 状態確認
make phase5
```

`make all` は `make phase1 -> make phase2 -> make bootstrap -> make phase5` を実行します。GitOps bootstrap の単独実行入口は `make bootstrap` です。

## 検証・チェック

```bash
# CI と同等の検証（推奨）
make validate

# Nix がローカルにある場合
nix develop .#default --command automation/scripts/ci/validate.sh

# 必要 toolchain が導入済みの場合のみ
make validate-local

# 個別チェック
shellcheck -S error -x automation/scripts/<file>.sh
yamllint -f parsable -c .yamllint.yml manifests/<dir-or-file>
kustomize build manifests/<kustomize-dir>
```

## ドキュメント

- 全体案内: `docs/README.md`
- セットアップ: `docs/bootstrap.md`
- アーキテクチャ: `docs/architecture.md`
- GitOps: `docs/gitops.md`
- マニフェスト配置: `docs/manifests.md`
- 運用: `docs/operations.md`
- トラブルシュート: `docs/troubleshooting.md`
