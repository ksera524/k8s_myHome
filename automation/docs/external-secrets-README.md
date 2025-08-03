# External Secrets Operator 運用ディレクトリ

## 📁 ディレクトリ構成

```
automation/platform/external-secrets/
├── README.md                           # このファイル
├── helm-deploy-eso.sh                  # Helm直接デプロイスクリプト（推奨）
├── migrate-to-argocd.sh                # Helm→ArgoCD管理移行スクリプト
├── setup-external-secrets.sh           # ArgoCD経由セットアップスクリプト
├── setup-pulumi-pat.sh                 # Pulumi Personal Access Token設定スクリプト
├── deploy-harbor-secrets.sh            # Harborシークレット自動デプロイスクリプト
├── deploy-slack-secrets.sh             # Slackシークレット自動デプロイスクリプト
├── test-harbor-secrets.sh              # 動作確認テストスクリプト
├── secretstores/
│   └── pulumi-esc-secretstore.yaml     # Pulumi ESC接続設定
├── externalsecrets/
│   ├── harbor-externalsecret.yaml      # Harbor管理者認証情報
│   ├── harbor-registry-externalsecret.yaml # Harbor Registry Secrets（全namespace対応）
│   ├── slack-externalsecret.yaml       # Slack認証情報（sandbox namespace）
│   ├── github-actions-externalsecret.yaml # GitHub Actions（作成予定）
│   └── applications/                   # アプリケーション別Secret（作成予定）
└── monitoring/
    ├── servicemonitor.yaml             # Prometheus監視（作成予定）
    └── alerts.yaml                     # Alert rules（作成予定）
```

## 🚀 使用方法

### 1. External Secrets Operator導入

```bash
# 方法1: Helmで直接デプロイ（推奨）
cd automation/platform/external-secrets
./helm-deploy-eso.sh

# 方法2: ArgoCD経由でのセットアップ
./setup-external-secrets.sh

# 方法3: make all 実行時の自動デプロイ
# k8s-infrastructure-deploy.sh が自動的にHelmデプロイを実行
```

### 2. Pulumi ESC認証設定

```bash
# 方法1: 対話モードでPATを設定
./setup-pulumi-pat.sh --interactive

# 方法2: 環境変数からPATを設定
export PULUMI_ACCESS_TOKEN="pul-xxxxx..."
echo "$PULUMI_ACCESS_TOKEN" | ./setup-pulumi-pat.sh

# 方法3: ファイルからPATを読み込み
./setup-pulumi-pat.sh < token-file.txt

# 確認
kubectl get secrets -A | grep pulumi-access-token
```

### 3. SecretStore設定適用

```bash
# Pulumi ESC SecretStore作成
kubectl apply -f secretstores/pulumi-esc-secretstore.yaml

# 接続確認
kubectl get secretstores --all-namespaces
```

### 4. Harbor Secret移行

```bash
# Pulumi ESCにHarborパスワード設定（事前設定が必要）
# HARBOR_ADMIN_PASSWORD=$(openssl rand -base64 32)
# HARBOR_CI_PASSWORD=$(openssl rand -base64 32)
# 
# pulumi esc env set ksera524/k8s-myhome/production \
#   harbor.admin_password "$HARBOR_ADMIN_PASSWORD" --secret
# 
# pulumi esc env set ksera524/k8s-myhome/production \
#   harbor.ci_password "$HARBOR_CI_PASSWORD" --secret

# Harbor Secrets自動デプロイ
./deploy-harbor-secrets.sh

# 作成されたSecret確認
kubectl get secrets -n harbor | grep harbor
kubectl get secrets -n arc-systems | grep harbor-registry
kubectl get secrets -n default | grep harbor-http
```

### 5. Slack Secret移行

```bash
# Pulumi ESCにSlack認証情報設定（事前設定が必要）
# SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
# SLACK_BOT_TOKEN="xoxb-..."
# SLACK_APP_TOKEN="xapp-..."
# 
# pulumi esc env set ksera/k8s/secret \
#   slack.webhook_url "$SLACK_WEBHOOK_URL" --secret
# pulumi esc env set ksera/k8s/secret \
#   slack.bot_token "$SLACK_BOT_TOKEN" --secret
# pulumi esc env set ksera/k8s/secret \
#   slack.app_token "$SLACK_APP_TOKEN" --secret
# pulumi esc env set ksera/k8s/secret \
#   slack.channel "#general"
# pulumi esc env set ksera/k8s/secret \
#   slack.username "bot"

# Slack Secrets自動デプロイ
./deploy-slack-secrets.sh

# 作成されたSecret確認
kubectl get secrets -n sandbox | grep slack
```

## 🔍 動作確認

### 基本確認コマンド

```bash
# ESO Pod状態
kubectl get pods -n external-secrets-system

# SecretStore状態
kubectl get secretstores --all-namespaces

# ExternalSecret状態
kubectl get externalsecrets --all-namespaces

# 作成されたSecret確認
kubectl get secrets --all-namespaces | grep -E "(harbor|github|slack)"
```

### 詳細確認

```bash
# ExternalSecret詳細状態
kubectl describe externalsecret harbor-admin-secret -n harbor
kubectl describe externalsecret slack-externalsecret -n sandbox

# ESO Controller ログ
kubectl logs -n external-secrets-system deployment/external-secrets -f

# Secret内容確認（デバッグ用）
kubectl get secret harbor-admin-secret -n harbor -o yaml
```

## 🔧 トラブルシューティング

### よくある問題

#### 1. SecretStore接続失敗
```bash
# 認証トークン確認
kubectl get secret pulumi-esc-auth -n external-secrets-system -o yaml

# Pulumi ESC接続テスト
pulumi esc env get ksera524/k8s-myhome/production
```

#### 2. ExternalSecret同期失敗
```bash
# 同期状態確認
kubectl get externalsecret harbor-admin-secret -n harbor -o yaml

# 手動同期強制実行
kubectl annotate externalsecret harbor-admin-secret \
  force-sync=$(date +%s) -n harbor
```

#### 3. Secret作成されない
```bash
# イベント確認
kubectl get events -n harbor --sort-by=.metadata.creationTimestamp

# ESO Controller ログ確認
kubectl logs -n external-secrets-system deployment/external-secrets --tail=50
```

## 📋 チェックリスト

### セットアップ完了確認
- [ ] External Secrets Operator Pod が Running
- [ ] 必要なCRDが作成済み
- [ ] Pulumi ESC認証設定完了
- [ ] SecretStore が Connected 状態
- [ ] Harbor ExternalSecret が Synced 状態
- [ ] Harbor Secret が作成済み

### セキュリティ確認
- [ ] 平文パスワードの設定ファイルからの削除
- [ ] Pulumi ESCアクセストークンの安全な保存
- [ ] Secret作成権限の適切な制限
- [ ] ネームスペース分離の実装

## 📚 関連ドキュメント

- [External Secrets Operatorインストールガイド](../../../docs/external-secrets-operator-installation-guide.md)
- [Pulumi ESC移行計画](../../../docs/pulumi-esc-migration-plan.md)
- [External Secrets Operator公式ドキュメント](https://external-secrets.io/)

## 🔗 automation統合

### k8s-infrastructure-deploy.sh 連携

External Secretsが設定されていない場合、`k8s-infrastructure-deploy.sh`は自動的にHelmでExternal Secrets Operatorをデプロイします：

```bash
# 方法1: 環境変数でPATを設定して実行（推奨）
export PULUMI_ACCESS_TOKEN="pul-xxxxx..."
cd automation/platform
./phase4-deploy.sh

# 方法2: 事前にPATを設定してから実行
cd external-secrets
./setup-pulumi-pat.sh --interactive
cd ../
./k8s-infrastructure-deploy.sh

# 自動処理フロー:
# 1. External Secrets Operator存在チェック
# 2. 未インストールの場合 -> Helmで直接デプロイ
# 3. デプロイ完了後 -> ArgoCD管理に移行（App-of-Apps設定済みの場合）
# 4. Harbor認証情報をPulumi ESCから自動取得
```

### 従来スクリプトからの移行

- `create-harbor-secrets.sh` → `deploy-harbor-secrets.sh` に置き換え
- 手動Secret作成から自動Pulumi ESC連携に変更
- 複数ネームスペースへの一括デプロイ対応

## 🎯 次のステップ

1. **GitHub Actions統合**: `externalsecrets/github-actions-externalsecret.yaml` の作成
2. **アプリケーション移行**: `externalsecrets/applications/` 配下のSecret作成
3. **監視設定**: `monitoring/` 配下の監視・アラート設定
4. **自動化拡張**: 追加のセットアップスクリプト作成