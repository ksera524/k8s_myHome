# Cutover チェックリスト

## 目的

- PH6 の cutover 判定を主観ではなく手順ベースで実施する

## 実施前（必須）

- [ ] main 凍結（merge 停止）
- [ ] 旧 main の tag 作成
- [ ] VM snapshot 取得
- [ ] etcd snapshot 取得
- [ ] stateful workload の backup 取得
- [ ] rollback 手順の確認（担当者付き）

## 実施中（必須）

- [ ] 新 bootstrap 入口のみ適用
- [ ] ArgoCD Application 全体が `Synced/Healthy` 到達
- [ ] 主要 Namespace の pod が `Ready` 到達
- [ ] legacy-removal-inventory の削除対象を削除

## 実施後（必須）

- [ ] 旧手順参照の grep 検証が 0 件
- [ ] policy 例外台帳で legacy 影響 `Yes` が 0 件
- [ ] docs の更新完了（README / setup / operations / troubleshooting / gitops-design）
- [ ] `tasks/backlog.md` に残課題を記録

## 判定

- 必須項目がすべて完了した場合のみ cutover 完了とする
