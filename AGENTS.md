# AGENTS.md
# k8s_myHome 用のエージェント運用ガイド

## 目的
- このリポジトリは home lab 向けの Kubernetes インフラ構築プロジェクト
- 変更は GitOps を前提に行い、manifests は `manifests/` 配下を使用する
- コメントや説明は日本語を基本とする

## プロジェクト概要

- ホームラボ向けの 3 ノード Kubernetes クラスタを仮想化基盤上で運用
- App-of-Apps パターンで GitOps 管理
- フェーズ実行（`make all`）で構築と検証を自動化

## アーキテクチャ概要

- Control Plane: `192.168.122.10`
- Worker: `192.168.122.11`, `192.168.122.12`
- LoadBalancer プール: `192.168.122.100-150`
- 主要コンポーネント: MetalLB, NGINX Gateway Fabric, cert-manager, ArgoCD, Harbor, ARC

## リポジトリ構成の要点
- `automation/`: 自動化スクリプト群
- `automation/infrastructure/`: VM + kubeadm によるクラスタ構築
- `automation/platform/`: 基本プラットフォーム構築
- `manifests/`: GitOps 用 Kubernetes マニフェスト
- `docs/`: 運用・設計ドキュメント

## GitOps の入口

- Root Application: `manifests/bootstrap/app-of-apps.yaml`

## 重要なルール
- 応答/コメントは日本語で記載
- k8s マニフェストは必ず `manifests/` 配下を利用
- App-of-Apps で ArgoCD 管理（GitOps を優先）
- App-of-Apps / Sync Wave の構成変更時は `docs/diagrams/app-of-apps-sync-wave.md` の Mermaid 図も更新する

## ビルド/検証/テストコマンド
このリポジトリにアプリ用ビルドはなく、検証中心

### 主要タスク
- `make all` : フェーズ1〜5を順番に実行
- `make phase1` / `make vm` : VM 構築
- `make phase2` / `make k8s` : k8s 構築
- `make phase3` / `make gitops-prep` : GitOps 準備
- `make phase4` / `make gitops-apps` : GitOps アプリ展開
- `make phase5` / `make verify` : 動作確認

### CI と検証スクリプト
- `automation/scripts/ci/validate.sh` を使用
  - shellcheck
  - yamllint
  - kustomize build

### 単一検証の例（single target）
- Shellcheck 単体: `shellcheck -S error -x automation/scripts/<file>.sh`
- Yamllint 単体: `yamllint -f parsable -c .yamllint.yml manifests/<dir-or-file>`
- Kustomize 単体: `kustomize build manifests/<kustomize-dir>`
- kubectlするときはssh k8suser@192.168.122.10してから実行すること

### テスト実行
- 自動テストフレームワークは未導入
- 代替として `make phase5` の検証ログと `automation/run.log` を参照

## スタイルガイド（全体）
### 言語/ドキュメント
- コメントは日本語
- ドキュメントは日本語を基本（必要なら英語併記）

### ディレクトリ規約
- GitOps 管理対象は `manifests/` のみ
- `automation/` はローカル実行用スクリプト

### 命名規則（Kubernetes）
- namespace: kebab-case（例: `arc-systems`）
- secret: 役割が分かる名前（例: `harbor-auth`, `github-auth`）
- リソース説明は日本語コメントを付ける

### 命名規則（ファイル/参照）
- ワイルドカード証明書: `wildcard-<scope>-cert.yaml`（例: `wildcard-external-cert.yaml` / `wildcard-internal-cert.yaml`）
- ワイルドカード証明書のリソース名: `wildcard-<scope>`、Secret 名: `wildcard-<scope>-tls`
- ExternalSecret 定義ファイル: `*-external-secret.yaml` を基本とする
- 複数 ExternalSecret をまとめるファイルは `external-secret-resources.yaml` とする

### YAML スタイル
- `yamllint` 設定: `.yamllint.yml`
- line-length: 最大 160
- truthy ルールは無効
- インデントは 2 スペースを基本

### Terraform スタイル
- インデントは 2 スペース
- コメントは日本語
- `resource`/`data`/`variable` を明確に分割

### Bash スタイル
- 先頭に `#!/usr/bin/env bash`
- 厳密モード: `set -euo pipefail`
- `local` でスコープを限定
- 既存の共通ログ関数を優先
  - `automation/scripts/common-logging.sh`
  - `log_status`, `log_warning`, `log_error` など

## import / 依存関係の扱い
- Shell: `source` は絶対パス/相対パスを明示
- 設定読込は `automation/scripts/settings-loader.sh` を利用
- 外部ツールは存在チェックを行う（例: `command -v yamllint`）

## エラーハンドリング
- 失敗時は即終了（`set -e`）
- パイプの失敗を検出（`pipefail`）
- 失敗時は `log_error` / 標準エラー出力で通知
- `ssh` 実行時は `StrictHostKeyChecking=no` を使う

## GitOps / マニフェスト運用
- App-of-Apps で ArgoCD 管理
- 変更は Git にコミットして ArgoCD 同期に反映

## 既知の検証フロー
- `automation/scripts/ci/validate.sh`
  - shellcheck: `automation/**.sh`
  - yamllint: `manifests/`, `automation/templates/`, `automation/infrastructure/`
  - kustomize: `manifests/**/kustomization.yaml`

## 推奨チェックコマンド
- ノード確認: `ssh k8suser@192.168.122.10 'kubectl get nodes'`
- ArgoCD 同期: `kubectl get applications -n argocd`
- Pod 状態: `kubectl get pods --all-namespaces`

## 変更時の注意
- 既存のログ/設定/デプロイフローを壊さない
- manifests のパスは `manifests/` に統一
- 追加したリソースは GitOps で管理できる状態にする

## CI / Workflow
- GitHub Actions: `.github/workflows/ci-deploy-validate.yml`
- CI では `validate.sh` を実行
- 依存ツール: shellcheck, yamllint, kustomize

## Cursor/Copilot ルール
- `.cursor/rules/`, `.cursorrules`, `.github/copilot-instructions.md` は未存在

## 補足
- `automation/run.log` に全ログが記録される
- `make phase5` が検証フェーズの入口
- 長時間実行前に `settings.toml` が設定済みか確認
- Runner 設定: minRunners=1（推奨）, maxRunners=3
