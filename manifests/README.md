# Kubernetes Manifests

このディレクトリには、k8s_myHomeプロジェクトのすべてのKubernetesマニフェストファイルが整理されています。

## ディレクトリ構造

```
manifests/
├── app-of-apps.yaml              # ArgoCD App-of-Apps パターンのメインアプリケーション
├── infrastructure/               # インフラストラクチャコンポーネント
│   ├── argocd/                   # ArgoCD設定とGitHub OAuth
│   ├── cert-manager/             # 証明書管理
│   ├── harbor/                   # プライベートコンテナレジストリ
│   ├── ingress-nginx/            # Ingressコントローラー
│   ├── metallb/                  # LoadBalancerサービス
│   └── storage/                  # ストレージクラス設定
├── external-secrets/             # External Secrets Operator設定
├── platform/                    # プラットフォームサービス
│   ├── github-actions/           # GitHub Actions Runner Controller
│   └── monitoring/               # 監視関連 (将来の拡張用)
└── applications/                 # ユーザーアプリケーション
    ├── cloudflared/              # Cloudflare Tunnel
    ├── hitomi/                   # 画像ビューア
    ├── pepup/                    # ポップアップサービス
    ├── rss/                      # RSSリーダー
    └── slack/                    # Slack統合
```

## 使用方法

### ArgoCD経由での管理
メインのapp-of-apps.yamlがすべてのコンポーネントを管理します：

```bash
kubectl apply -f manifests/app-of-apps.yaml
```

### 個別コンポーネントのデプロイ
特定のコンポーネントのみをデプロイする場合：

```bash
# ArgoCD設定のみ
kubectl apply -f manifests/infrastructure/argocd/

# Harbor関連のみ
kubectl apply -f manifests/infrastructure/harbor/
```

## 移行履歴

以前は以下の場所に分散していたmanifestファイルを整理しました：
- `/infra/` - メインのインフラマニフェスト
- `/app/` - アプリケーションマニフェスト  
- `/automation/platform/manifests/` - プラットフォームデプロイ用
- `/automation/platform/external-secrets/` - External Secrets関連

## 注意事項

- GitOpsワークフローでは、このディレクトリのmanifestファイルがArgoCD経由で自動同期されます
- 手動変更する場合は、対応するgitリポジトリへのコミットも忘れずに行ってください
- External Secretsは秘密情報をPulumi ESCから動的に取得します