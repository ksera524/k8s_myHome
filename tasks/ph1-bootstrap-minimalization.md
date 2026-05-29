# PH1: Bootstrap Minimalization

## 目的

- 初回 bootstrap の失敗要因を除去し、再構築可能性を高める
- bootstrap と steady-state の境界を明確化し、bootstrap 入口を最小責務に固定する

## 背景

- bootstrap と steady-state の責務が混在し、依存順不整合が発生しやすい

## スコープ

- ArgoCD 初期導入に必要な最小リソース定義
- ESO 依存リソースの後段移動
- bootstrap 手順の分離
- pre-ESO 適用可能リソースと post-ESO リソースの明確分離

## 非ゴール

- アプリ delivery 方式の変更

## 具体タスク

1. bootstrap 対象リソースを最小セットとして再定義
2. pre-ESO で適用される `ExternalSecret` を禁止し、post-ESO へ移動
3. `manifests/platform/argocd-config/` の pre-ESO 依存（例: registry ExternalSecret）を分離
4. `automation/platform/platform-deploy.sh` の steady-state 処理（patch/restart/sync強制）を切り出し
5. `automation/scripts/app-deploy.sh` を bootstrap 入口専用に整理
6. bootstrap と steady-state のディレクトリ境界を定義
7. 初回構築向け smoke test 項目を定義

## 変更対象

- `manifests/bootstrap/`
- `manifests/platform/argocd-config/`
- `manifests/platform/secrets/`
- `automation/platform/`
- `automation/scripts/setup-eso-prerequisites.sh`
- `automation/scripts/app-deploy.sh`

## 検証

1. fresh cluster で bootstrap 手順を 2 回再実行し、どちらも手動介入なしで完了すること
2. ESO 未導入時点で ExternalSecret 依存エラーを発生させないこと
3. bootstrap 実行後に「手動 patch/restart なし」で PH2 へ進めること
4. 検証ログ（`automation/run.log` または同等ログ）に重大エラーが残っていないこと

## 完了条件

1. bootstrap と steady-state の責務が分離されている
2. pre-ESO で `ExternalSecret` が適用されない
3. 初回構築の主要手順がドキュメント化されている
4. smoke test 観点が定義済み
5. bootstrap 入口の責務が ArgoCD root 適用までに限定されている
