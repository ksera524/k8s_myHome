# External Secrets GitOps セットアップガイド

## 概要
External Secrets Operator (ESO) のリソースをGitOpsで管理するためのセットアップが完了しました。

## 変更内容

### 1. Kustomizationファイルの追加
以下のKustomizationファイルを追加し、ESOリソースをGitOps管理下に置きました：

- `manifests/platform/kustomization.yaml`
- `manifests/platform/secrets/external-secrets/kustomization.yaml`

### 2. platform-deploy.shの改善
- 手動でのClusterSecretStore作成を削除
- ArgoCD Platform Applicationの同期をトリガーして、ESOリソースを自動適用
- ESOリソースの作成状態を確認するステップを追加

## 動作確認方法

### 1. クリーンインストールでの確認
```bash
# クラスター全体を再構築
cd automation/infrastructure
./clean-and-deploy.sh

# プラットフォームをデプロイ（ESOリソースも自動適用される）
cd ../platform
./platform-deploy.sh
```

### 2. ESOリソースの確認
```bash
# ClusterSecretStore確認
kubectl get clustersecretstore pulumi-esc-store

# ExternalSecrets確認
kubectl get externalsecrets -A

# アプリケーションPodの状態確認
kubectl get pods -n cloudflared
kubectl get pods -n slack
```

### 3. ArgoCD経由での同期確認
```bash
# Platform Applicationの状態確認
kubectl get application platform -n argocd -o yaml | grep -A5 status:

# 手動同期が必要な場合
kubectl patch application platform -n argocd --type merge -p '{"operation": {"sync": {"syncStrategy": {"hook": {}}}}}'
```

## トラブルシューティング

### ClusterSecretStoreが作成されない場合
1. Platform Applicationの同期状態を確認
2. Pulumi Access Tokenが正しく設定されているか確認
3. External Secrets Operatorのログを確認：
   ```bash
   kubectl logs -n external-secrets-system deployment/external-secrets
   ```

### ExternalSecretsが同期されない場合
1. ClusterSecretStoreの状態を確認：
   ```bash
   kubectl describe clustersecretstore pulumi-esc-store
   ```
2. ExternalSecretの詳細を確認：
   ```bash
   kubectl describe externalsecret cloudflared-secret -n cloudflared
   ```

## アーキテクチャ
```
ArgoCD (App-of-Apps)
├── Core Application
├── Infrastructure Application
├── Platform Application ← ここでESOリソースを管理
│   └── manifests/platform/
│       ├── secrets/external-secrets/
│       │   ├── pulumi-esc-secretstore.yaml
│       │   ├── externalsecrets.yaml
│       │   ├── app-externalsecrets.yaml
│       │   └── kustomization.yaml
│       └── kustomization.yaml
└── Applications
    └── cloudflared, slack等（ESOで作成されたSecretを使用）
```

## メリット
1. **完全なGitOps化**: すべてのESOリソースがGitで管理される
2. **自動復旧**: ArgoCD self-healingによりリソースが自動的に復旧
3. **バージョン管理**: Gitによる変更履歴の追跡が可能
4. **宣言的管理**: kubectl applyの手動実行が不要