# External Secrets Operator インストールガイド

## 🎯 導入方針

k8s_myHomeプロジェクトでは、**ArgoCD App-of-Appsパターン**でExternal Secrets Operatorを導入します。
既存のGitOpsワークフローに完全統合し、段階的にSecret管理を自動化します。

## 📊 導入方法比較

| 方法 | メリット | デメリット | k8s_myHome適用 |
|------|----------|------------|----------------|
| **Helm直接** | シンプル・迅速 | GitOps統合なし | ❌ 不適合 |
| **kubectl直接** | カスタマイズ容易 | 手動管理必要 | ❌ 不適合 |
| **ArgoCD App-of-Apps** | GitOps完全統合 | 初期設定複雑 | ✅ 推奨 |

## 🗓️ 段階的導入スケジュール

### Phase 1: ESO基盤構築 (1日)
**実施場所**: `automation/platform/`
**目標**: External Secrets Operatorの基本導入

### Phase 2: Pulumi ESC統合 (1日)  
**実施場所**: `automation/platform/external-secrets/`
**目標**: SecretStore設定とテスト

### Phase 3: Harbor緊急移行 (1日)
**実施場所**: `automation/platform/external-secrets/`
**目標**: 最高優先度のHarbor認証情報移行

### Phase 4: GitHub Actions統合 (2日)
**実施場所**: `automation/platform/external-secrets/`
**目標**: CI/CDパイプライン完全自動化

### Phase 5: アプリケーション移行 (2日)
**実施場所**: `infra/external-secrets/`
**目標**: 全アプリケーションSecret自動化

## 📁 ファイル構成

```
# 基盤設定（ArgoCD管理）
infra/
├── app-of-apps.yaml                      # ESO Application追加
└── external-secrets/
    ├── external-secrets-operator-app.yaml # ArgoCD Application定義
    ├── operator-values.yaml               # Helm values
    └── rbac.yaml                          # 追加RBAC設定

# 運用設定（Platform管理）
automation/platform/external-secrets/
├── README.md
├── setup-external-secrets.sh             # 自動化スクリプト
├── secretstores/
│   ├── pulumi-esc-secretstore.yaml       # Pulumi ESC接続
│   └── backup-secretstore.yaml           # バックアップ用
├── externalsecrets/
│   ├── harbor-externalsecret.yaml        # Harbor認証
│   ├── github-actions-externalsecret.yaml # GitHub Actions
│   └── applications/
│       ├── slack-externalsecret.yaml     # Slack Bot
│       ├── cloudflared-externalsecret.yaml # Cloudflare Tunnel
│       └── hitomi-externalsecret.yaml    # Hitomi
└── monitoring/
    ├── servicemonitor.yaml               # Prometheus監視
    └── alerts.yaml                       # Alert rules
```

## 🚀 Phase 1: ESO基盤構築

### 1.1 ArgoCD Application作成

```yaml
# infra/external-secrets/external-secrets-operator-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-secrets-operator
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: 'https://charts.external-secrets.io'
    targetRevision: '0.18.2'
    chart: external-secrets
    helm:
      values: |
        installCRDs: true
        replicaCount: 1
        resources:
          limits:
            cpu: 100m
            memory: 128Mi
          requests:
            cpu: 10m
            memory: 32Mi
        serviceMonitor:
          enabled: true
          additionalLabels:
            release: prometheus
        webhook:
          replicaCount: 1
        certController:
          replicaCount: 1
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: external-secrets-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - Replace=true
  ignoreDifferences:
  - group: apiextensions.k8s.io
    kind: CustomResourceDefinition
    jqPathExpressions:
    - '.spec.conversion.webhook.clientConfig.caBundle'
```

### 1.2 App-of-Apps更新

```yaml
# infra/app-of-apps.yamlに追加
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-secrets-operator
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/ksera524/k8s_myHome.git
    targetRevision: HEAD
    path: infra/external-secrets
    directory:
      include: "external-secrets-operator-app.yaml"
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### 1.3 動作確認

```bash
# 1. ArgoCD Application同期確認
kubectl get applications -n argocd | grep external-secrets

# 2. ESO Pod起動確認
kubectl get pods -n external-secrets-system

# 3. CRD確認
kubectl get crd | grep external-secrets

# 4. サービス確認
kubectl get svc -n external-secrets-system
```

## 🔧 Phase 2: Pulumi ESC統合

### 2.1 Pulumi ESC認証設定

```bash
# Pulumi ESCアクセストークン作成
pulumi auth create --scopes "esc:read,esc:decrypt"

# Kubernetes Secretとして設定
kubectl create secret generic pulumi-esc-auth \
  --from-literal=access-token="$PULUMI_ACCESS_TOKEN" \
  -n external-secrets-system
```

### 2.2 SecretStore設定

```yaml
# automation/platform/external-secrets/secretstores/pulumi-esc-secretstore.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: pulumi-esc-store
  namespace: external-secrets-system
spec:
  provider:
    pulumi:
      organization: "ksera524"
      project: "k8s-myhome"  
      environment: "production"
      accessToken:
        secretRef:
          name: pulumi-esc-auth
          key: access-token
```

### 2.3 接続テスト

```yaml
# テスト用ExternalSecret
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: test-connection
  namespace: default
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: pulumi-esc-store
    kind: SecretStore
  target:
    name: test-secret
  data:
  - secretKey: test-value
    remoteRef:
      key: test.message
```

```bash
# テスト実行
kubectl apply -f test-externalsecret.yaml

# 結果確認
kubectl get secret test-secret -o yaml
kubectl describe externalsecret test-connection
```

## 🔒 Phase 3: Harbor緊急移行

### 3.1 Pulumi ESC環境設定

```bash
# 強力なパスワード生成
HARBOR_ADMIN_PASSWORD=$(openssl rand -base64 32)
HARBOR_CI_PASSWORD=$(openssl rand -base64 32)

# Pulumi ESCに設定
pulumi esc env set ksera524/k8s-myhome/production \
  harbor.admin_password "$HARBOR_ADMIN_PASSWORD" --secret

pulumi esc env set ksera524/k8s-myhome/production \
  harbor.ci_password "$HARBOR_CI_PASSWORD" --secret
```

### 3.2 Harbor ExternalSecret作成

```yaml
# automation/platform/external-secrets/externalsecrets/harbor-externalsecret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: harbor-admin-secret
  namespace: harbor
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: pulumi-esc-store
    kind: SecretStore
  target:
    name: harbor-admin-secret
    creationPolicy: Owner
    template:
      type: Opaque
      data:
        # Harbor Core用
        HARBOR_ADMIN_PASSWORD: "{{ .adminPassword }}"
        # CI/CD用  
        HARBOR_CI_PASSWORD: "{{ .ciPassword }}"
        # Registry認証用
        .dockerconfigjson: |
          {
            "auths": {
              "192.168.122.100": {
                "username": "admin",
                "password": "{{ .adminPassword }}",
                "auth": "{{ printf "admin:%s" .adminPassword | b64enc }}"
              }
            }
          }
  data:
  - secretKey: adminPassword
    remoteRef:
      key: harbor.admin_password
  - secretKey: ciPassword
    remoteRef:
      key: harbor.ci_password
```

### 3.3 Harbor設定更新

```bash
# 既存の平文パスワード削除
cd automation/platform
sed -i 's/Harbor12345/{{ .Values.adminPassword }}/g' *.yaml
sed -i 's/CIUser12345/{{ .Values.ciPassword }}/g' *.yaml

# Harbor Pod再起動（新しいSecretを取得）
kubectl rollout restart deployment/harbor-core -n harbor
```

## 🔨 Phase 4: GitHub Actions統合

### 4.1 GitHub App作成・設定

```bash
# GitHub App情報をPulumi ESCに設定
pulumi esc env set ksera524/k8s-myhome/production \
  github.app_id "$GITHUB_APP_ID" --secret

pulumi esc env set ksera524/k8s-myhome/production \
  github.private_key "$GITHUB_PRIVATE_KEY" --secret

pulumi esc env set ksera524/k8s-myhome/production \
  github.installation_id "$GITHUB_INSTALLATION_ID" --secret
```

### 4.2 GitHub ExternalSecret作成

```yaml
# automation/platform/external-secrets/externalsecrets/github-actions-externalsecret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: github-actions-controller
  namespace: arc-systems
spec:
  refreshInterval: 2h
  secretStoreRef:
    name: pulumi-esc-store
    kind: SecretStore
  target:
    name: github-multi-repo-secret
    creationPolicy: Merge  # 既存Secretにマージ
  data:
  - secretKey: github_app_id
    remoteRef:
      key: github.app_id
  - secretKey: github_app_private_key
    remoteRef:
      key: github.private_key
  - secretKey: github_app_installation_id
    remoteRef:
      key: github.installation_id
```

### 4.3 Actions Runner Controller更新

```bash
# Controller Pod再起動
kubectl rollout restart deployment/arc-controller-gha-rs-controller -n arc-systems

# Runner動作確認
kubectl get runners --all-namespaces
```

## 📱 Phase 5: アプリケーション移行

### 5.1 アプリケーション環境設定

```yaml
# Pulumi ESC環境にアプリケーション設定追加
applications:
  slack3:
    bot_token:
      fn::secret: "xoxb-your-slack-bot-token"
    signing_secret:
      fn::secret: "your-slack-signing-secret"
      
  cloudflared:
    tunnel_token:
      fn::secret: "your-cloudflare-tunnel-token"
      
  hitomi:
    database_password:
      fn::secret: "your-database-password"
    api_key:
      fn::secret: "your-api-key"
```

### 5.2 アプリケーション別ExternalSecret

```yaml
# infra/external-secrets/applications/slack3-externalsecret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: slack3-secrets
  namespace: slack3
spec:
  refreshInterval: 4h
  secretStoreRef:
    name: pulumi-esc-store
    kind: SecretStore
  target:
    name: slack3
    creationPolicy: Owner
  data:
  - secretKey: token
    remoteRef:
      key: applications.slack3.bot_token
  - secretKey: signing_secret
    remoteRef:
      key: applications.slack3.signing_secret
```

## 🔍 動作確認・監視

### 基本確認コマンド

```bash
# 1. ESO Pod状態
kubectl get pods -n external-secrets-system

# 2. 全ExternalSecret状態
kubectl get externalsecrets --all-namespaces

# 3. 作成されたSecret確認
kubectl get secrets --all-namespaces | grep -E "(harbor|github|slack|cloudflared)"

# 4. 同期状態詳細
kubectl describe externalsecret harbor-admin-secret -n harbor

# 5. ESO Controller ログ
kubectl logs -n external-secrets-system deployment/external-secrets -f

# 6. メトリクス確認
kubectl port-forward -n external-secrets-system svc/external-secrets-metrics 8080:8080
curl http://localhost:8080/metrics | grep external_secrets
```

### トラブルシューティング

```bash
# Secret同期失敗時
kubectl get events -n harbor --sort-by=.metadata.creationTimestamp

# SecretStore接続テスト
kubectl get secretstore pulumi-esc-store -o yaml

# 手動同期強制実行
kubectl annotate externalsecret harbor-admin-secret \
  force-sync=$(date +%s) -n harbor
```

## 🎯 成功指標

### 技術指標
- [ ] ESO Pod が healthy で動作中
- [ ] 全SecretStore が Connected 状態
- [ ] ExternalSecret同期率 99%以上
- [ ] Secret取得時間 30秒以内

### セキュリティ指標
- [ ] 平文SecretのGitリポジトリ完全削除
- [ ] RBAC設定による適切なアクセス制御
- [ ] 認証情報の暗号化保存
- [ ] 監査ログの取得

## 📚 次のステップ

Phase 1完了後、以下の順序で実装を進めてください：

1. **Phase 1実行**: ArgoCD経由でESO導入
2. **動作確認**: 基本的なSecret同期テスト
3. **Phase 2実行**: Pulumi ESC接続設定
4. **Phase 3実行**: Harbor緊急移行
5. **Phase 4-5実行**: 段階的なアプリケーション移行

各Phase完了時に動作確認を必ず実施し、問題があれば次のPhaseに進まないことを推奨します。

---

**作成日**: 2025-01-23  
**最終更新**: 2025-01-23  
**バージョン**: 1.0  
**作成者**: Claude Code