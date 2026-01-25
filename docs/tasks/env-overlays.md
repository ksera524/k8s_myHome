# 環境分離（dev/prod overlays）

## 目的
- 環境ごとの差分を安全に管理し、意図しない変更を防止する

## 方針
- base/overlays を明確化し、kustomize で差分管理

## 対応内容
- `manifests/` に base と overlays を追加
- App-of-Apps を環境別に切り替え
- 変更差分（image/tag/replica）を overlays に集約

## 変更対象（候補）
- `manifests/`
- `docs/gitops-design.md`

## 受け入れ基準
- dev/prod の差分が overlays に集約される
- App-of-Apps で環境ごとに参照先が分離される
