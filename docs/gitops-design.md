# GitOps設計

## 概要

k8s_myHomeプロジェクトは、ArgoCDを使用したGitOpsパターンを採用しています。すべてのKubernetesリソースはGitリポジトリで宣言的に管理され、ArgoCDによって自動的に同期されます。

## GitOpsアーキテクチャ

### App-of-Appsパターン

```
┌─────────────────────────────────────────────────┐
│              Root Application                    │
│   (bootstrap/app-of-apps.yaml)                  │
└──────────────┬──────────────────────────────────┘
               │
    ┌──────────┴───────────┬──────────┬──────────┐
    │                      │          │          │
┌───▼────┐         ┌──────▼────┐ ┌──▼──┐  ┌────▼────┐
│ Core   │         │Platform   │ │Infra│  │  Apps   │
│ Apps   │         │Services   │ │     │  │         │
└────────┘         └───────────┘ └─────┘  └─────────┘
    │                   │           │          │
    ├─ namespaces      ├─ ArgoCD   ├─ MetalLB ├─ Slack
    ├─ storage-class   ├─ Harbor   ├─ NGINX   ├─ RSS
    └─ rbac            └─ ESO      └─ Cert    └─ Hitomi
```

### デプロイメント Wave

ArgoCDのSync Wavesを使用して、依存関係を考慮した順序でデプロイ：

| Wave | コンポーネント | 説明 |
|------|-------------|------|
| 1 | Local Path Provisioner | ストレージプロビジョナー |
| 2 | Core (Namespaces) | 基本リソース |
| 3 | MetalLB | LoadBalancer |
| 4 | MetalLB Config | IPプール設定 |
| 5 | NGINX Ingress | Ingressコントローラー |
| 6 | cert-manager | 証明書管理 |
| 7 | cert-manager Config | Issuer設定 |
| 7 | External Secrets | シークレット管理 |
| 10 | Platform Services | ArgoCD, Harbor |
| 11 | User App Definitions | アプリケーション定義 |
| 12 | User Applications | 実際のアプリケーション |
| 13 | Harbor Patches | Harbor後処理 |

## ディレクトリ構造

```
manifests/
├── bootstrap/
│   └── app-of-apps.yaml         # ルートApplication
├── config/
│   └── secrets/                 # 外部連携用シークレット
├── core/
│   ├── namespaces/              # Namespace定義
│   └── storage-classes/         # StorageClass定義
├── infrastructure/
│   ├── networking/
│   │   └── metallb/             # MetalLB設定
│   ├── security/
│   │   └── cert-manager/        # 証明書管理
│   └── gitops/
│       └── harbor/              # Harborパッチ
├── monitoring/
│   └── grafana-k8s-monitoring-values.yaml  # 監視用values（未接続）
├── platform/
│   ├── argocd-config/           # ArgoCD設定
│   ├── ci-cd/
│   │   └── github-actions/      # ARC設定
│   └── secrets/
│       └── external-secrets/    # ESO設定
└── apps/
    ├── cloudflared/             # アプリケーション
    ├── hitomi/
    ├── pepup/
    ├── rss/
    └── slack/
```

## GitOps運用の境界と配置規約

- GitOps 管理対象は `manifests/` 配下のみ（ArgoCD が同期）
- `automation/` はローカル実行用で GitOps 対象外（VM/クラスタ構築や運用補助）
- 新規アプリは `manifests/apps/<app-name>/` に配置し、App-of-Apps から参照する
- 共通基盤は `manifests/core/`、`manifests/infrastructure/`、`manifests/platform/` に分類
- 手動での kubectl 適用は一時対応に留め、最終的には Git に反映する

例外:
- GitHub Actions Runner は `add-runner.sh` による作成運用（GitOps 管理外）

## ArgoCD設定

### Application定義

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: example-app
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "10"  # デプロイ順序
spec:
  project: default
  source:
    repoURL: https://github.com/ksera524/k8s_myHome.git
    targetRevision: main
    path: manifests/apps/example
  destination:
    server: https://kubernetes.default.svc
    namespace: example
  syncPolicy:
    automated:
      prune: true        # 削除されたリソースを自動削除
      selfHeal: true     # 手動変更を自動修正
    syncOptions:
    - CreateNamespace=true  # Namespace自動作成
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### 同期ポリシー

#### 自動同期

- **Interval**: 3分（デフォルト）
- **Prune**: 有効（Gitから削除されたリソースを自動削除）
- **Self Heal**: 有効（手動変更を自動的に修正）

#### 手動同期が必要なケース

- Critical なリソース（CRD、Namespace等）
- データベース関連の変更
- 破壊的な変更

### Health Assessment

```yaml
# カスタムヘルスチェック例
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  resource.customizations.health.argoproj.io_Application: |
    hs = {}
    if obj.status ~= nil then
      if obj.status.health ~= nil then
        hs.status = obj.status.health.status
        hs.message = obj.status.health.message
      end
    end
    return hs
```

## Secret管理

### External Secrets Operator

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: pulumi-esc-store
spec:
  provider:
    pulumi:
      organization: "ksera"
      project: "k8s"
      environment: "secret"
      accessToken:
        secretRef:
          name: pulumi-access-token
          key: access_token
```

### Secret同期フロー

```
Pulumi ESC → ClusterSecretStore → ExternalSecret → K8s Secret
```

### ExternalSecret定義例

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-secret
  namespace: sandbox
spec:
  refreshInterval: 20s
  secretStoreRef:
    name: pulumi-esc-store
    kind: ClusterSecretStore
  target:
    name: app-secret
    creationPolicy: Owner
  data:
  - secretKey: api-key
    remoteRef:
      key: api-key
```

## カスタマイゼーション

### Kustomization使用

```yaml
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml

patches:
  - target:
      kind: Deployment
      name: myapp
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 3
```

### Helm統合

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  source:
    repoURL: https://charts.example.com
    chart: mychart
    targetRevision: 1.2.3
    helm:
      parameters:
      - name: image.tag
        value: v1.0.0
      values: |
        replicaCount: 2
        resources:
          limits:
            memory: 256Mi
```

## CI/CD統合

### GitHub Actions Workflow

```yaml
name: Deploy to K8s
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: k8s-myhome-runners  # Self-hosted runner
    steps:
      - uses: actions/checkout@v3
      
      - name: Build and Push to Harbor
        run: |
          docker build -t harbor.qroksera.com/sandbox/${{ github.repository }}:${{ github.sha }} .
          docker push harbor.qroksera.com/sandbox/${{ github.repository }}:${{ github.sha }}
      
      - name: Update Manifest
        run: |
          sed -i "s|image:.*|image: harbor.qroksera.com/sandbox/${{ github.repository }}:${{ github.sha }}|" manifests/apps/myapp/deployment.yaml
          
      - name: Commit and Push
        run: |
          git config user.name "GitHub Actions"
          git config user.email "actions@github.com"
          git add manifests/apps/myapp/deployment.yaml
          git commit -m "Update image to ${{ github.sha }}"
          git push
```

### ArgoCD Image Updater（オプション）

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: myapp=harbor.qroksera.com/sandbox/myapp
    argocd-image-updater.argoproj.io/myapp.update-strategy: latest
    argocd-image-updater.argoproj.io/myapp.pull-secret: pullsecret:arc-systems/harbor-registry-secret
```

## モニタリングと可観測性

### Application メトリクス

```bash
# Application状態
kubectl get applications -n argocd

# 同期状態の詳細
kubectl get application <app-name> -n argocd -o jsonpath='{.status}'

# ヘルス状態
kubectl get application <app-name> -n argocd -o jsonpath='{.status.health.status}'
```

### Prometheus メトリクス

ArgoCD は Prometheus メトリクスを公開：

- `argocd_app_info` - Application情報
- `argocd_app_health_status` - ヘルス状態
- `argocd_app_sync_total` - 同期回数

## ベストプラクティス

### 1. リポジトリ構造

- 環境ごとにディレクトリを分離
- アプリケーションごとにディレクトリを作成
- 共通設定は base ディレクトリに配置

### 2. 同期戦略

- Production: 手動同期推奨
- Staging: 自動同期 + Self Heal
- Development: 完全自動同期

### 3. リソース管理

```yaml
# リソース制限の設定
resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 100m
    memory: 128Mi
```

### 4. ラベルとアノテーション

```yaml
metadata:
  labels:
    app.kubernetes.io/name: myapp
    app.kubernetes.io/instance: production
    app.kubernetes.io/version: "1.0.0"
    app.kubernetes.io/component: backend
    app.kubernetes.io/part-of: myapp-suite
    app.kubernetes.io/managed-by: argocd
```

### 5. プログレッシブデリバリー

Flagger や Argo Rollouts との統合を検討：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
spec:
  strategy:
    canary:
      steps:
      - setWeight: 20
      - pause: {duration: 10m}
      - setWeight: 40
      - pause: {duration: 10m}
      - setWeight: 60
      - pause: {duration: 10m}
      - setWeight: 80
      - pause: {duration: 10m}
```

## トラブルシューティング

### 同期が失敗する

```bash
# 同期エラーの詳細確認
kubectl describe application <app-name> -n argocd

# 手動同期を強制実行
argocd app sync <app-name> --force

# リソースの差分確認
argocd app diff <app-name>
```

### OutOfSync が解消しない

```bash
# ハードリフレッシュ
kubectl patch application <app-name> -n argocd \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# 特定リソースを無視
kubectl annotate <resource> argocd.argoproj.io/sync-options=Prune=false
```

### Health が Degraded

```bash
# Pod の状態確認
kubectl get pods -n <namespace>

# イベント確認
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# ログ確認
kubectl logs -n <namespace> <pod-name>
```

## まとめ

GitOps は k8s_myHome プロジェクトの中核となる設計パターンです。ArgoCDのApp-of-Appsパターンにより、複雑な依存関係を持つアプリケーションスタックを宣言的に管理し、自動化されたデプロイメントを実現しています。
