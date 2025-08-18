# Pulumi ESC Secret管理移行計画

## 🎯 移行目標

- Pulumi ESC (Environments, Secrets, and Configuration) による統合Secret管理
- External Secrets Operatorによる自動同期
- GitOpsワークフローとの完全統合
- SecretとConfigurationの一元管理

## 📊 Pulumi ESC vs HCP Vault Secrets 比較

| 項目 | Pulumi ESC | HCP Vault Secrets |
|------|------------|-------------------|
| **ライセンス** | Apache 2.0 (オープンソース) | Business Source License |
| **管理方式** | フルマネージドSaaS | マネージドまたは自己管理 |
| **料金** | $0.50-0.75/secret/月 | $0.03/secret/月 |
| **Secret種別** | Static + Dynamic + Configuration | Secretのみ |
| **K8s統合** | ESO + CSI Driver | ESO + Agent |
| **環境管理** | 環境コンポジション・継承 | 限定的 |
| **学習コスト** | 低（統合UI・CLI） | 中（Vault専用知識） |

### k8s_myHomeでPulumi ESCを選択する理由

1. **GitOps親和性**: ArgoCD + Kubernetes環境に自然に統合
2. **オープンソース**: ライセンス制約なし
3. **統合管理**: SecretとConfigurationを一元管理
4. **環境継承**: development → staging → production の構成管理

## 📊 移行対象Secret分析

| Secret種別 | 現在の管理方法 | 緊急度 | 移行複雑度 | 推定工数 |
|------------|----------------|--------|------------|----------|
| **Harbor認証情報** | 平文設定ファイル | 🔴 最高 | 低 | 1日 |
| **GitHubトークン** | ローカルファイル | 🔴 高 | 中 | 2日 |
| **アプリケーションSecret** | 未作成 | 🟡 高 | 低 | 2日 |
| **ArgoCD認証** | K8s Secret | 🟡 中 | 低 | 0.5日 |
| **SSL/TLS証明書** | cert-manager | 🟢 低 | 低 | 0.5日 |

## 🗓️ 段階的移行プラン

### Phase 1: 基盤構築 (1週間)
**目標**: Pulumi ESC環境とExternal Secrets Operator導入

#### 1.1 Pulumi ESC環境構築
```bash
# Pulumi ESC組織・プロジェクト作成
pulumi org create ksera524
pulumi esc env init ksera524/k8s-myhome/production

# 環境設定
pulumi esc env set ksera524/k8s-myhome/production \
  --file environment.yaml
```

#### 1.2 環境定義設計
```yaml
# production environment
values:
  cluster:
    name: "k8s-myhome"
    metallb_ip_range: "192.168.122.100-150"
    
  harbor:
    admin_password:
      fn::secret: "HarborSecure2024!"
    ci_password:
      fn::secret: "CIUserSecure2024!"
    url: "192.168.122.100"
    
  github:
    app_id:
      fn::secret: "123456"
    private_key:
      fn::secret: |
        -----BEGIN RSA PRIVATE KEY-----
        [ENCRYPTED_KEY_CONTENT]
        -----END RSA PRIVATE KEY-----
    installation_id:
      fn::secret: "987654"
```

#### 1.3 External Secrets Operator導入
```bash
# automation/platform配下に導入
kubectl apply -f external-secrets-operator.yaml
```

### Phase 2: Harbor緊急移行 (1日)
**目標**: セキュリティリスク最高のHarborパスワード即座対応

#### 2.1 新しいパスワード生成・設定
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

#### 2.2 Harbor ExternalSecret作成
```yaml
# automation/platform/pulumi-esc/harbor-externalsecret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: harbor-secrets
  namespace: harbor
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: SecretStore
    name: pulumi-esc-store
  target:
    name: harbor-admin-secret
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: harbor.admin_password
    - secretKey: ci_password
      remoteRef:
        key: harbor.ci_password
```

### Phase 3: GitHub Actions統合 (2日)
**目標**: GitHub Actions Runner完全自動化

#### 3.1 GitHub App作成・設定
```bash
# GitHub App情報をPulumi ESCに設定
pulumi esc env set ksera524/k8s-myhome/production \
  github.app_id "$GITHUB_APP_ID" --secret

pulumi esc env set ksera524/k8s-myhome/production \
  github.private_key "$GITHUB_PRIVATE_KEY" --secret
```

#### 3.2 GitHub ExternalSecret作成
```yaml
# automation/platform/pulumi-esc/github-externalsecret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: github-actions-secrets
  namespace: arc-systems
spec:
  refreshInterval: 2h
  secretStoreRef:
    kind: SecretStore
    name: pulumi-esc-store
  target:
    name: github-multi-repo-secret
    creationPolicy: Merge
  data:
    - secretKey: github_app_id
      remoteRef:
        key: github.app_id
    - secretKey: github_app_private_key
      remoteRef:
        key: github.private_key
```

#### 3.3 既存スクリプト更新
```bash
# automation/platform/github-auth-utils.sh を更新
# ローカルファイル管理 → Pulumi ESC参照に変更
```

### Phase 4: アプリケーション移行 (2日)
**目標**: 全アプリケーションSecret自動化

#### 4.1 アプリケーション環境設定
```yaml
# Pulumi ESC環境にアプリケーション設定追加
applications:
  slack3:
    token:
      fn::secret: "xoxb-slack-bot-token"
    signing_secret:
      fn::secret: "slack-signing-secret"
      
  cloudflared:
    token:
      fn::secret: "cloudflare-tunnel-token"
      
  hitomi:
    database_password:
      fn::secret: "hitomi-db-password"
    api_key:
      fn::secret: "hitomi-api-key"
```

#### 4.2 アプリケーション別ExternalSecret作成
```yaml
# infra/pulumi-esc/applications/slack3-externalsecret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: slack3-secrets
  namespace: slack3
spec:
  refreshInterval: 4h
  secretStoreRef:
    kind: SecretStore
    name: pulumi-esc-store
  target:
    name: slack3
    creationPolicy: Owner
  data:
    - secretKey: token
      remoteRef:
        key: applications.slack3.token
    - secretKey: signing_secret
      remoteRef:
        key: applications.slack3.signing_secret
```

### Phase 5: ArgoCD統合 (0.5日)
**目標**: GitOpsワークフローでSecret管理

#### 5.1 ArgoCD Application作成
```yaml
# infra/pulumi-esc/external-secrets-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-secrets
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/ksera524/k8s_myHome'
    targetRevision: HEAD
    path: infra/pulumi-esc
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: external-secrets
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Phase 6: 運用最適化 (1日)
**目標**: 監視・アラート設定

#### 6.1 監視設定
```yaml
# monitoring/pulumi-esc-monitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: external-secrets-monitor
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: external-secrets
  endpoints:
  - port: metrics
    interval: 30s
```

## 🏗️ 実装アーキテクチャ

```mermaid
graph TB
    subgraph "Pulumi ESC"
        ESC[Pulumi ESC SaaS]
        ESC --> Harbor[Harbor Secrets]
        ESC --> GitHub[GitHub Secrets]
        ESC --> Apps[Application Secrets]
        ESC --> Config[Configuration]
    end
    
    subgraph "Kubernetes Cluster"
        ESO[External Secrets Operator]
        K8sSecrets[Kubernetes Secrets]
        ESO --> K8sSecrets
    end
    
    subgraph "Applications"
        ArgoCD[ArgoCD]
        ActionsRunner[Actions Runner]
        HarborApp[Harbor]
        UserApps[User Applications]
    end
    
    ESC --> ESO
    K8sSecrets --> ArgoCD
    K8sSecrets --> ActionsRunner  
    K8sSecrets --> HarborApp
    K8sSecrets --> UserApps
```

## 📁 ファイル構成

```
automation/platform/
├── pulumi-esc/
│   ├── setup-pulumi-esc.sh
│   ├── external-secrets-operator.yaml
│   ├── secretstore-config.yaml
│   ├── harbor-externalsecret.yaml
│   ├── github-externalsecret.yaml
│   └── migration-scripts/
│       ├── harbor-migration.sh
│       ├── github-migration.sh
│       └── app-migration.sh

infra/pulumi-esc/
├── external-secrets-app.yaml
├── secretstore.yaml
└── applications/
    ├── slack3-externalsecret.yaml
    ├── cloudflared-externalsecret.yaml
    ├── hitomi-externalsecret.yaml
    ├── rss-externalsecret.yaml
    └── pepup-externalsecret.yaml

docs/
├── pulumi-esc-migration-plan.md
└── pulumi-esc-operations-guide.md
```

## 💰 コスト見積もり

### Secret数見積もり
```yaml
estimated_secrets:
  harbor: 2           # admin_password, ci_password
  github: 3          # app_id, private_key, installation_id  
  applications: 15   # 5アプリ × 3 secret/app
  infrastructure: 5  # ArgoCD, cert-manager等
  total: 25 secrets
```

### 月額コスト計算
| プラン | 単価/secret/月 | 25 secrets月額 | 年額 |
|--------|----------------|-----------------|------|
| **Team Edition** | $0.50 | $12.50 | $150 |
| **Enterprise** | $0.75 | $18.75 | $225 |
| **個人利用** | 無料 | $0 | $0 |

### HCP Vault Secretsとの比較
| 項目 | Pulumi ESC | HCP Vault Secrets |
|------|------------|-------------------|
| 25 secrets月額 | $12.50 | $0.75 |
| 年額 | $150 | $9 |
| **差額** | **+$141/年** | - |

## 🔒 セキュリティ考慮事項

### 1. アクセス制御
```yaml
# Pulumi ESC RBAC設定例
team_permissions:
  - team: "k8s-admins"
    environments:
      - "k8s-myhome/production"
    permission: "admin"
    
  - team: "developers"
    environments:
      - "k8s-myhome/development"
    permission: "read"
```

### 2. 監査・コンプライアンス
- アクセスログの記録
- Secret使用状況の追跡
- 定期的なセキュリティレビュー
- OIDC統合による動的認証

### 3. ネットワークセキュリティ
- HTTPS通信の強制
- Kubernetes内部通信の暗号化
- Service Mesh統合（オプション）

## 🚀 実装開始提案

### 即座に開始すべき作業

1. **Pulumi ESCアカウント設定** (今日)
   ```bash
   # Pulumi Cloud登録
   pulumi login
   pulumi org create ksera524
   ```

2. **Harborパスワード緊急変更** (今日)
   ```bash
   # 設定ファイルから平文削除
   sed -i 's/Harbor12345/PLACEHOLDER/g' automation/platform/*
   ```

3. **External Secrets Operator準備** (明日)
   ```bash
   cd automation/platform
   ./setup-external-secrets.sh
   ```

### 段階的実装スケジュール

| 週 | フェーズ | 主要タスク | 成果物 |
|----|---------|------------|---------|
| **Week 1** | Phase 1-2 | ESC環境構築 + Harbor移行 | Harbor自動化 |
| **Week 2** | Phase 3 | GitHub Actions統合 | CI/CD自動化 |
| **Week 3** | Phase 4-5 | アプリ移行 + ArgoCD統合 | 全Secret自動化 |
| **Week 4** | Phase 6 | 運用最適化 | 監視・アラート |

## 📝 移行チェックリスト

### Phase 1: 基盤構築
- [ ] Pulumi ESCアカウント作成
- [ ] k8s-myhome組織・プロジェクト作成
- [ ] production環境初期設定
- [ ] External Secrets Operator導入
- [ ] SecretStore設定・テスト

### Phase 2: Harbor緊急移行
- [ ] 新しいHarborパスワード生成
- [ ] Pulumi ESCへのSecret設定
- [ ] Harbor ExternalSecret作成
- [ ] 動作確認・テスト
- [ ] 平文パスワード削除

### Phase 3: GitHub統合
- [ ] GitHub App作成
- [ ] App認証情報のESC設定
- [ ] GitHub ExternalSecret作成
- [ ] Actions Runner Controller更新
- [ ] CI/CDパイプライン動作確認

### Phase 4: アプリケーション移行
- [ ] アプリケーション要件分析
- [ ] 各アプリのSecret設定
- [ ] ExternalSecret定義作成
- [ ] アプリケーション動作確認

### Phase 5: ArgoCD統合
- [ ] ArgoCD Application作成
- [ ] GitOps同期設定
- [ ] 自動デプロイ確認

### Phase 6: 運用最適化
- [ ] 監視設定
- [ ] アラート設定
- [ ] ドキュメント整備
- [ ] セキュリティ監査

## 🔧 トラブルシューティング

### よくある問題と解決方法

#### 1. Pulumi ESC認証失敗
```bash
# トークン確認
pulumi whoami
pulumi esc env get ksera524/k8s-myhome/production

# 再認証
pulumi logout
pulumi login
```

#### 2. ExternalSecret同期失敗
```bash
# ESO Controller ログ確認
kubectl logs -n external-secrets-system \
  deployment/external-secrets -f

# SecretStore設定確認
kubectl describe secretstore pulumi-esc-store
```

#### 3. Secret値が更新されない
```bash
# 手動同期強制実行
kubectl annotate externalsecret harbor-secrets \
  force-sync=$(date +%s) -n harbor

# refresh間隔確認
kubectl get externalsecret harbor-secrets -o yaml | grep refreshInterval
```

## 📚 参考資料

- [Pulumi ESC公式ドキュメント](https://www.pulumi.com/docs/esc/)
- [External Secrets Operator Pulumi Provider](https://external-secrets.io/latest/provider/pulumi/)
- [Pulumi ESC Kubernetes統合ガイド](https://www.pulumi.com/docs/esc/integrations/kubernetes/)

## 📊 成功指標

### 技術指標
- [ ] 全Secretが平文でGitリポジトリに含まれない
- [ ] Secret変更時の自動同期が30分以内に完了
- [ ] アプリケーションが自動的にSecretを取得できる
- [ ] 99.9%のSecret同期成功率

### セキュリティ指標
- [ ] 平文Secretの完全削除
- [ ] アクセス監査ログの取得
- [ ] RBAC設定による適切なアクセス制御
- [ ] Secret使用状況の可視化

### 運用指標
- [ ] Secret更新作業の自動化率100%
- [ ] 緊急時対応時間30分以内
- [ ] 監視アラートの適切な設定
- [ ] ドキュメント整備完了

---

**作成日**: 2025-01-23  
**最終更新**: 2025-01-23  
**バージョン**: 1.0  
**作成者**: Claude Code