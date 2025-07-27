# External Secrets 統合クイックセットアップガイド

`make all` 実行時に External Secrets Operator が見つからない場合の対処方法

## 🎯 推奨解決方法

### 方法1: Pulumi ESC Personal Access Token を環境変数で設定

```bash
# 1. Pulumi ESC でアクセストークンを取得
# https://app.pulumi.com/account/tokens

# 2. 環境変数を設定してから make all を実行
export PULUMI_ACCESS_TOKEN="pul-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
make all
```

### 方法2: 事前にExternal Secretsをセットアップ

```bash
# 1. External Secrets Operatorをセットアップ
cd automation/platform/external-secrets
./setup-external-secrets.sh

# 2. Pulumi Access Tokenを設定
./setup-pulumi-pat.sh --interactive

# 3. Harbor Secretsをデプロイ
./deploy-harbor-secrets.sh

# 4. 通常の automation を実行
cd ../
make all
```

## 🔧 フォールバック動作について

External Secrets が利用できない場合、自動的に従来の手動管理方式に切り替わります：

- Harbor管理者パスワードはデフォルト値 `Harbor12345` が使用されます
- 手動でパスワードを変更する場合は、後でHarborの設定を更新してください

## 📋 推奨設定手順

1. **Pulumi ESCの設定**
   ```bash
   # Pulumi ESC環境にHarborパスワードを設定
   pulumi esc env set ksera524/k8s-myhome/production \
     harbor.admin_password "$(openssl rand -base64 32)" --secret
   
   pulumi esc env set ksera524/k8s-myhome/production \
     harbor.ci_password "$(openssl rand -base64 32)" --secret
   ```

2. **アクセストークンの取得**
   - https://app.pulumi.com/account/tokens にアクセス
   - `Create Token` をクリック
   - `ESC (Environments, Secrets, and Configuration)` スコープを選択
   - 生成されたトークンをコピー

3. **環境変数での実行**
   ```bash
   export PULUMI_ACCESS_TOKEN="pul-xxxxxxxx..."
   make all
   ```

## 🚨 トラブルシューティング

### External Secrets Operator が見つからない場合

```bash
# ArgoCD Applicationの状態確認
kubectl get applications -n argocd | grep external-secrets

# 手動でArgoCD同期を実行
kubectl patch application external-secrets-operator -n argocd \
  --type merge -p '{"operation":{"sync":{"force":true}}}'

# External Secrets Operator のPod確認
kubectl get pods -n external-secrets-system
```

### Pulumi Access Token の問題

```bash
# Secret確認
kubectl get secrets -A | grep pulumi-access-token

# Pulumi ESC接続テスト
pulumi esc env get ksera524/k8s-myhome/production

# SecretStore状態確認
kubectl describe secretstore pulumi-esc-store -n harbor
```

## ✅ 動作確認

```bash
# External Secrets による Harbor 認証情報の確認
cd automation/platform/external-secrets
./test-harbor-secrets.sh
```

## 📝 その他の注意事項

- External Secrets は既に `infra/app-of-apps.yaml` に登録済みです
- ArgoCD による自動デプロイが前提の設計になっています
- フォールバック機能により、External Secrets なしでも基本機能は動作します
- セキュリティのため、本番環境では必ずExternal Secretsの使用を推奨します