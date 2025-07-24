# External Secrets Operator 運用ディレクトリ

## 📁 ディレクトリ構成

```
automation/platform/external-secrets/
├── README.md                           # このファイル
├── setup-external-secrets.sh           # 自動セットアップスクリプト
├── secretstores/
│   └── pulumi-esc-secretstore.yaml     # Pulumi ESC接続設定
├── externalsecrets/
│   ├── harbor-externalsecret.yaml      # Harbor認証情報
│   ├── github-actions-externalsecret.yaml # GitHub Actions（作成予定）
│   └── applications/                   # アプリケーション別Secret（作成予定）
└── monitoring/
    ├── servicemonitor.yaml             # Prometheus監視（作成予定）
    └── alerts.yaml                     # Alert rules（作成予定）
```

## 🚀 使用方法

### 1. External Secrets Operator導入

```bash
# 自動セットアップ実行
cd automation/platform/external-secrets
./setup-external-secrets.sh
```

### 2. Pulumi ESC認証設定

```bash
# Pulumi ESCアクセストークン作成
pulumi auth create --scopes "esc:read,esc:decrypt"

# Kubernetes Secretとして設定
kubectl create secret generic pulumi-esc-auth \
  --from-literal=access-token="$PULUMI_ACCESS_TOKEN" \
  -n external-secrets-system

# 各namespaceにも作成（必要に応じて）
kubectl create secret generic pulumi-esc-auth \
  --from-literal=access-token="$PULUMI_ACCESS_TOKEN" \
  -n harbor

kubectl create secret generic pulumi-esc-auth \
  --from-literal=access-token="$PULUMI_ACCESS_TOKEN" \
  -n actions-runner-system
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
# Pulumi ESCにHarborパスワード設定
HARBOR_ADMIN_PASSWORD=$(openssl rand -base64 32)
HARBOR_CI_PASSWORD=$(openssl rand -base64 32)

pulumi esc env set ksera524/k8s-myhome/production \
  harbor.admin_password "$HARBOR_ADMIN_PASSWORD" --secret

pulumi esc env set ksera524/k8s-myhome/production \
  harbor.ci_password "$HARBOR_CI_PASSWORD" --secret

# ExternalSecret適用
kubectl apply -f externalsecrets/harbor-externalsecret.yaml

# 作成されたSecret確認
kubectl get secrets -n harbor | grep harbor
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
kubectl get secrets --all-namespaces | grep -E "(harbor|github)"
```

### 詳細確認

```bash
# ExternalSecret詳細状態
kubectl describe externalsecret harbor-admin-secret -n harbor

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

## 🎯 次のステップ

1. **GitHub Actions統合**: `externalsecrets/github-actions-externalsecret.yaml` の作成
2. **アプリケーション移行**: `externalsecrets/applications/` 配下のSecret作成
3. **監視設定**: `monitoring/` 配下の監視・アラート設定
4. **自動化拡張**: 追加のセットアップスクリプト作成