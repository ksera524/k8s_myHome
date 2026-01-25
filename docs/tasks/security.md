# セキュリティ（PSA/NetworkPolicy/RBAC）

## 目的
- 最小権限と通信制御を標準化し、事故と侵害面を縮小する

## 方針
- Pod Security Admission を namespace 単位で適用
- NetworkPolicy のデフォルト拒否を基本とする

## 対応内容
- PSA ラベルの運用方針と適用
- NetworkPolicy テンプレート作成（deny-all + 例外）
- RBAC 権限の棚卸しと最小化

## 変更対象（候補）
- `manifests/core/`
- `manifests/platform/`
- `docs/operations-guide.md`

## 受け入れ基準
- 主要 namespace に PSA が適用済み
- NetworkPolicy が適用されている
- RBAC の権限が明文化されている
