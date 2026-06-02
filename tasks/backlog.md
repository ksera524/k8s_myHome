# 改革後バックログ

## 目的

- PH6 完了後に残る改善項目を管理する
- 完了済み改革スコープと追加改善を分離する

## 記入ルール

- PH6 完了条件を満たした後の課題のみ記載する
- 優先度（High/Medium/Low）と owner を必須とする
- 期限が必要なものは期限を記載する

## Backlog Items

| ID | 内容 | 優先度 | Owner | 期限 | 状態 |
|---|---|---|---|---|---|
| B-001 | 代替監視基盤（self-hosted もしくは別 SaaS）の要件整理、配置先、導入順序を設計する。設計正本は `tasks/observability-plan.md`。runtime owner の初期実装は VictoriaMetrics + kube-state-metrics | Medium | platform | TBD | Implementing |
