# Kubernetes Manifests

このディレクトリには、k8s_myHomeプロジェクトのKubernetesマニフェストを整理しています。

## ディレクトリ構造

```
manifests/
├── bootstrap/                    # ArgoCD App-of-Apps
├── core/                         # 基本リソース（namespace, storage-class など）
├── infrastructure/               # インフラ構成（networking, security など）
├── platform/                     # プラットフォームサービス（ArgoCD, ESO, ARC）
├── monitoring/                   # 監視関連（manifests/values）
└── apps/                         # ユーザーアプリケーション
```

## 使用方法

### ArgoCD経由での管理
App-of-Apps がすべてのコンポーネントを管理します。

```bash
kubectl apply -f manifests/bootstrap/app-of-apps.yaml
```

### 個別コンポーネントのデプロイ
緊急時の暫定対応のみ。最終的には Git に反映します。

```bash
# MetalLB
kubectl apply -f manifests/infrastructure/networking/metallb/

# ArgoCD設定
kubectl apply -f manifests/platform/argocd-config/
```

## 注意事項

- GitOpsワークフローでは、このディレクトリのマニフェストがArgoCD経由で自動同期されます
- 手動変更は一時対応に留め、対応する Git へのコミットを必ず行ってください
- ExternalSecret 定義は manifests/platform/secrets/external-secrets/ に集約しています
- External Secrets は Pulumi ESC から動的に取得します
