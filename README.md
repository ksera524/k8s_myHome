# k8s_myHome
おうちk8sクラスタの管理リポジトリ

## 構成図

![](./diagrams/diagram.svg)

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

## 検証・チェック

```bash
# CI と同等の検証
automation/scripts/ci/validate.sh

# 個別チェック
shellcheck -S error -x automation/scripts/<file>.sh
yamllint -f parsable -c .yamllint.yml manifests/<dir-or-file>
kustomize build manifests/<kustomize-dir>
```

## ドキュメント

- 全体案内: `docs/README.md`
- GitOps 設計: `docs/gitops-design.md`
- セットアップ: `docs/quickstart.md`
- 運用: `docs/operations-guide.md`
- トラブルシュート: `docs/troubleshooting.md`
