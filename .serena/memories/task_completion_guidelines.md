# タスク完了時のガイドライン

## 検証とテスト
- Kubernetesマニフェスト変更後は必ず `kubectl apply --dry-run=client` で構文確認
- Terraform変更後は `terraform plan` で影響範囲確認
- シェルスクリプト変更後は `shellcheck` でのスタイルチェック推奨
- SSH接続確認: `ssh -o ConnectTimeout=10 k8suser@192.168.122.10`

## セキュリティチェック
- 秘密情報のハードコーディング避ける
- External Secrets Operatorの使用を優先
- 手動 `kubectl create secret` は最小限に抑制
- パスワードや認証情報はk8s Secretsで管理

## GitOps反映
- マニフェスト変更後はArgoCD同期を確認
- App-of-Apps パターンでの整合性チェック
- `kubectl get applications -n argocd` でアプリケーション状態確認

## ドキュメント更新
- 重要な設定変更は CLAUDE.md の更新を検討
- 新規機能追加時は使用方法をコメントで日本語説明
- 破壊的変更はマイグレーション手順も記載

## コミットとプッシュ
```bash
git add .
git commit -m "日本語での簡潔な変更説明"
git push
```

## エラーハンドリング
- スクリプトは `set -euo pipefail` でエラー時即座停止
- 重要な外部コマンドは戻り値チェック
- ログレベル（INFO/WARNING/ERROR/DEBUG）適切に使用