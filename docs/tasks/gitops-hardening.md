# GitOps強化（Project/RBAC/Sync）

## 目的
- ArgoCD の権限分離と同期制御を強化し、誤変更とドリフトを防止する

## 方針
- Project 単位で管理対象の namespace/cluster を制限
- 重要変更は Sync Window/承認フローを通す

## 対応内容
- ArgoCD Project の追加（用途/環境別）
- Application の Project 紐付け
- Sync Window と自動同期ポリシーの見直し
- 変更禁止領域（kube-system など）の明示

## 変更対象（候補）
- `manifests/platform/argocd-config/`
- `manifests/bootstrap/`

## 受け入れ基準
- Project ごとに同期対象が制限されている
- 重要リソースは手動同期/承認に切り替えられる
- 既存 Application が正しい Project に紐付く
