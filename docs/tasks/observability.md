# 可観測性（監視/ログ/アラート）

## 目的
- 主要コンポーネントの状態を可視化し、障害検知と一次対応を高速化する

## 方針
- Prometheus/Loki/Grafana を標準構成として運用
- 重要アラートを最小セットで定義

## 対応内容
- 監視スタックの GitOps 追加
- 主要アラート（NodeNotReady, PodCrashLoop, PVCPending, GatewayError）定義
- 監視ダッシュボードの基準セット作成

## 変更対象（候補）
- `manifests/monitoring/`
- `docs/operations-guide.md`

## 受け入れ基準
- 監視スタックが ArgoCD 管理で稼働
- 主要アラートが通知される
- 運用ガイドに一次対応手順がある
