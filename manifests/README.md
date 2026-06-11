# Kubernetes Manifests

このディレクトリには、k8s_myHomeプロジェクトのKubernetesマニフェストを整理しています。

## ディレクトリ構造

```
manifests/
├── bootstrap/                    # ArgoCD App-of-Apps
├── core/                         # 基本リソース（namespace, storage-class など）
├── infrastructure/               # インフラ構成（networking, security など）
├── platform/                     # プラットフォームサービス（ArgoCD, ESO, ARC）
├── access/                       # 公開/接続系リソース
├── contracts/                    # 非機密 environment / access contract
└── apps/                         # ユーザーアプリケーション
```

## 使用方法

GitOps が正です。通常は repo root から `make bootstrap` を実行し、ArgoCD App-of-Apps に管理を委譲します。

```bash
make bootstrap
```

root `Application` は `manifests/bootstrap/app-of-apps.yaml` です。bootstrap 後の core / infrastructure / platform / access / apps は child `Application` が同期します。

### 個別確認

個別コンポーネントは原則 apply せず、build や差分確認に留めます。

```bash
kustomize build manifests/core
kustomize build manifests/access/gateway
```

緊急時に手動 `kubectl apply` した場合も、一時対応に留め、最終状態は必ず Git に反映してください。

## 注意事項

- GitOpsワークフローでは、このディレクトリのマニフェストがArgoCD経由で自動同期されます
- `bootstrap/` には Root/Application 定義のみを置きます
- 手動変更は一時対応に留め、対応する Git へのコミットを必ず行ってください
- ExternalSecret 定義は `manifests/platform/secrets/external-secrets/` に集約しています
- External Secrets は Pulumi ESC から動的に取得します

詳細な配置規約は `docs/manifests.md` を参照してください。
