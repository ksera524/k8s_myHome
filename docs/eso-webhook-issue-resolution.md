# External Secrets Operator Webhook問題の解決

## 問題の概要

External Secrets Operator (ESO) のValidatingWebhookが自己署名証明書を使用しているため、ArgoCDからリソースを作成する際に以下のエラーが発生：

```
failed calling webhook "validate.externalsecret.external-secrets.io": 
tls: failed to verify certificate: x509: certificate signed by unknown authority
```

## 根本原因

1. **ESO Webhookの設計**: ESOは自己署名証明書でValidatingWebhookを実装
2. **ArgoCDの動作**: ArgoCDはkube-apiserverを通じてリソースを作成し、kube-apiserverがwebhookを呼び出す
3. **証明書検証の失敗**: kube-apiserverがESO webhookの自己署名証明書を信頼できない

## 実装した解決策

### 1. Webhook無効化（開発環境推奨）

開発環境ではValidatingWebhookを無効化することで問題を根本的に解決：

#### a. Helm値による無効化
`manifests/bootstrap/app-of-apps.yaml`:
```yaml
webhook:
  create: false
certController:
  create: false
```

#### b. ValidatingWebhookConfiguration削除
`automation/platform/platform-deploy.sh`:
```bash
kubectl delete validatingwebhookconfiguration externalsecret-validate --ignore-not-found=true
kubectl delete validatingwebhookconfiguration secretstore-validate --ignore-not-found=true
```

### 2. 緊急修正スクリプト

問題が発生した場合の手動修正用：

```bash
./automation/scripts/eso-webhook-fix.sh
```

## なぜWebhook無効化が適切か

### 開発環境での利点
- **シンプル**: 証明書管理の複雑さを回避
- **安定性**: ArgoCDとの互換性問題を完全に解決
- **メンテナンス不要**: 証明書の更新や管理が不要

### 本番環境での考慮事項

本番環境では以下の代替案を検討：

1. **cert-managerによる証明書管理**
   - cert-managerでwebhook用の証明書を発行
   - ValidatingWebhookConfigurationにCAバンドルを設定

2. **admission webhookの選択的有効化**
   - 特定のnamespaceのみwebhookを有効化
   - ArgoCDが管理するnamespaceを除外

## トラブルシューティング

### 症状の確認
```bash
# ESO Webhookのログ確認
kubectl logs -n external-secrets-system deploy/external-secrets-operator-webhook

# ValidatingWebhookConfiguration確認
kubectl get validatingwebhookconfigurations | grep -E "external|secret"

# ArgoCD Application同期エラー確認
kubectl describe application platform -n argocd
```

### 修正の適用
```bash
# 自動修正（make all実行時に適用）
cd automation/platform && ./platform-deploy.sh

# 手動修正
./automation/scripts/eso-webhook-fix.sh
```

## 今後の改善案

1. **環境別設定**: 開発/本番で異なる設定を適用
2. **cert-manager統合**: 本番環境向けに証明書管理を自動化
3. **監視強化**: ESO関連のエラーを早期検出

## 参考リンク

- [External Secrets Operator Documentation](https://external-secrets.io/)
- [ArgoCD Webhook Configuration](https://argo-cd.readthedocs.io/en/stable/)
- [Kubernetes Admission Webhooks](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/)