# k8s_myHome 運用改善計画書

## エグゼクティブサマリー

本ドキュメントは、k8s_myHomeプロジェクトの包括的な調査結果に基づく運用改善計画です。調査により、**12件の主要改善点**を特定し、優先度別に分類しました。

### 改善点の優先度別分類
- 🔴 **Critical（即座対応）**: ~~2件~~ → **1件** (1件対応済み✅) - セキュリティリスク
- 🟡 **High（1週間以内）**: 4件 - 運用安定性に影響
- 🔵 **Medium（1ヶ月以内）**: 4件 - 品質向上
- ⚪ **Low（計画的実施）**: 2件 - 最適化

### 対応済み項目
✅ **ハードコーディングされた認証情報の削除** (2025-01-23対応)
- settings.toml.exampleのHarbor12345パスワード削除
- setup-arc.shのハードコーディングパスワード削除
- ESO経由での動的取得に変更

---

## 1. Critical - 即座に対応すべき問題

### 1.1 ハードコーディングされた認証情報の除去 ✅ **対応済み**

**問題点** (解決済み)
- ~~settings.toml.exampleにハードコーディングされたパスワード "Harbor12345"~~
- ~~setup-arc.shにハードコーディングされたパスワード~~

**実施した対応**
1. `automation/settings.toml.example`:
   - `admin_password = "Harbor12345"` を削除
   - コメントアウトして環境変数またはESO経由での設定を明記

2. `automation/scripts/github-actions/setup-arc.sh`:
   - ハードコーディングされたパスワードを削除
   - ESO (External Secrets Operator) から動的に取得するように変更
   - エラーハンドリングを追加（パスワード取得失敗時は処理を停止）

**新しい実装**
```bash
# ESOからHarborパスワードを取得
HARBOR_PASSWORD=$(kubectl get secret harbor-admin-secret -n harbor -o jsonpath='{.data.password}' | base64 -d)
if [[ -z "$HARBOR_PASSWORD" ]]; then
    echo "エラー: ESOからHarborパスワードを取得できませんでした"
    exit 1
fi
```

**実装手順**
```bash
# 1. settings-loader.sh を更新
cat >> automation/scripts/settings-loader.sh << 'EOF'
# 環境変数からの読み込み機能
load_from_env() {
    local key="$1"
    local env_var="$2"
    local value="${!env_var:-}"
    
    if [[ -n "$value" ]]; then
        export "$key=$value"
        log_debug "Loaded $key from environment variable"
    fi
}

# 必須環境変数のチェック
check_required_env() {
    local required_vars=("HARBOR_ADMIN_PASSWORD" "GITHUB_USERNAME" "GITHUB_TOKEN")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required environment variable $var is not set"
            return 1
        fi
    done
}
EOF

# 2. .env.example ファイルを作成
cat > .env.example << 'EOF'
# 必須環境変数
export HARBOR_ADMIN_PASSWORD=""
export GITHUB_USERNAME=""
export GITHUB_TOKEN=""
export PULUMI_ACCESS_TOKEN=""
EOF

# 3. README に環境変数の設定方法を追記
```

### 1.2 NetworkPolicyの実装

**問題点**
- すべてのPod間通信が無制限
- 外部からの不正アクセスリスク

**改善案**
```yaml
# manifests/infrastructure/security/network-policies/default-deny.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  
---
# manifests/infrastructure/security/network-policies/allow-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
```

---

## 2. High Priority - 1週間以内に対応すべき問題

### 2.1 Podリソース制限の設定

**問題点**
- RSS、Hitomi、Pepupアプリケーションでリソース制限未設定
- リソース枯渇のリスク

**改善案**
```yaml
# 各アプリケーションのmanifest.yamlに追加
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
```

**一括適用スクリプト**
```bash
#!/bin/bash
# automation/scripts/apply-resource-limits.sh

APPS=("rss" "hitomi" "pepup" "slack")

for app in "${APPS[@]}"; do
    manifest="manifests/apps/$app/manifest.yaml"
    if [[ -f "$manifest" ]]; then
        # yqを使用してリソース制限を追加
        yq eval '.spec.template.spec.containers[0].resources = {
            "requests": {"cpu": "100m", "memory": "128Mi"},
            "limits": {"cpu": "500m", "memory": "256Mi"}
        }' -i "$manifest"
        echo "Applied resource limits to $app"
    fi
done
```

### 2.2 SecurityContextの実装

**問題点**
- rootユーザーでの実行
- 書き込み可能なファイルシステム

**改善案**
```yaml
# 各Deploymentに追加
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      containers:
      - name: app
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
```

### 2.3 監視システムの導入

**問題点**
- メトリクスの収集なし
- アラート機能なし

**改善案**
```yaml
# manifests/platform/monitoring/kube-prometheus-stack.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kube-prometheus-stack
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "5"
spec:
  project: platform
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    targetRevision: 56.0.0
    chart: kube-prometheus-stack
    helm:
      values: |
        prometheus:
          prometheusSpec:
            storageSpec:
              volumeClaimTemplate:
                spec:
                  accessModes: ["ReadWriteOnce"]
                  resources:
                    requests:
                      storage: 10Gi
        grafana:
          adminPassword: changeme
          persistence:
            enabled: true
            size: 1Gi
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

### 2.4 バックアップ戦略の実装

**問題点**
- データバックアップなし
- 災害復旧計画なし

**改善案**
```yaml
# manifests/platform/backup/velero.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: velero
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "4"
spec:
  project: platform
  source:
    repoURL: https://vmware-tanzu.github.io/helm-charts
    targetRevision: 5.0.0
    chart: velero
    helm:
      values: |
        configuration:
          provider: aws
          backupStorageLocation:
            bucket: k8s-backup
            config:
              region: us-east-1
              s3ForcePathStyle: true
              s3Url: http://minio.minio.svc:9000
        schedules:
          daily-backup:
            schedule: "0 2 * * *"
            template:
              ttl: "720h0m0s"
              includedNamespaces:
              - default
              - harbor
              - argocd
```

---

## 3. Medium Priority - 1ヶ月以内に対応すべき問題

### 3.1 ドキュメントの整合性修正

**問題点**
- CLAUDE.mdの記載と実際のディレクトリ構造の不一致

**改善案**
```bash
# docs/update-documentation.sh
#!/bin/bash

# 実際のディレクトリ構造をスキャンしてドキュメントを更新
generate_structure() {
    echo "## 実際のディレクトリ構造"
    tree -d -L 3 manifests/ automation/
}

# CLAUDE.md を更新
update_claude_md() {
    # バックアップ作成
    cp CLAUDE.md CLAUDE.md.bak
    
    # 構造セクションを更新
    generate_structure > /tmp/structure.txt
    # sedやawkを使用して該当セクションを置換
}
```

### 3.2 重複Application定義の削除

**問題点**
- manifests/apps/配下に個別の*-app.yamlファイルが重複存在

**改善案**
```bash
# クリーンアップスクリプト
#!/bin/bash
# automation/scripts/cleanup-duplicates.sh

DUPLICATE_FILES=(
    "manifests/apps/rss-app.yaml"
    "manifests/apps/slack-app.yaml"
    "manifests/bootstrap/applications/harbor-app.yaml"
)

for file in "${DUPLICATE_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        echo "Removing duplicate: $file"
        git rm "$file"
    fi
done

git commit -m "Remove duplicate Application definitions"
```

### 3.3 エラーハンドリングの強化

**問題点**
- スクリプトのリトライ機能不足
- 部分的失敗からの復旧困難

**改善案**
```bash
# automation/scripts/retry-helper.sh
#!/bin/bash

retry_with_backoff() {
    local max_attempts="${1:-3}"
    local delay="${2:-5}"
    local max_delay="${3:-60}"
    shift 3
    
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if "$@"; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            echo "Command failed (attempt $attempt/$max_attempts), retrying in ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))
            [[ $delay -gt $max_delay ]] && delay=$max_delay
        fi
        
        ((attempt++))
    done
    
    echo "Command failed after $max_attempts attempts"
    return 1
}

# 使用例
retry_with_backoff 5 2 30 kubectl apply -f manifest.yaml
```

### 3.4 CI/CDパイプラインの改善

**問題点**
- テストの自動化不足
- デプロイメント検証の欠如

**改善案**
```yaml
# .github/workflows/ci.yml
name: CI Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Validate Kubernetes manifests
      run: |
        kubectl apply --dry-run=client -f manifests/
    
    - name: Lint shell scripts
      run: |
        shellcheck automation/**/*.sh
    
    - name: Security scan
      uses: aquasecurity/trivy-action@master
      with:
        scan-type: 'config'
        scan-ref: '.'
        
  test-deployment:
    runs-on: self-hosted
    needs: validate
    steps:
    - name: Deploy to test namespace
      run: |
        kubectl create namespace test-${{ github.sha }} || true
        kubectl apply -f manifests/ -n test-${{ github.sha }}
        
    - name: Run smoke tests
      run: |
        ./automation/tests/smoke-tests.sh test-${{ github.sha }}
        
    - name: Cleanup
      if: always()
      run: |
        kubectl delete namespace test-${{ github.sha }}
```

---

## 4. Low Priority - 計画的に実施する改善

### 4.1 パフォーマンス最適化

**改善案**
```bash
# VM起動の並列化
parallel_vm_start() {
    local vms=("control-plane" "worker-1" "worker-2")
    for vm in "${vms[@]}"; do
        virsh start "k8s-$vm" &
    done
    wait
}
```

### 4.2 ログ集約システム

**改善案**
```yaml
# manifests/platform/logging/elastic-stack.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: elastic-stack
  namespace: argocd
spec:
  source:
    repoURL: https://helm.elastic.co
    chart: elasticsearch
    targetRevision: 8.11.1
```

---

## 5. 実装ロードマップ

### Week 1 (Critical + High開始)
- [ ] Day 1-2: 認証情報の環境変数化
- [ ] Day 2-3: NetworkPolicy実装
- [ ] Day 3-5: リソース制限追加
- [ ] Day 5-7: SecurityContext実装

### Week 2-4 (High完了 + Medium開始)
- [ ] Week 2: 監視システム導入
- [ ] Week 2: バックアップ戦略実装
- [ ] Week 3: ドキュメント更新
- [ ] Week 3: 重複定義削除
- [ ] Week 4: エラーハンドリング強化

### Month 2 (Medium完了 + Low開始)
- [ ] CI/CDパイプライン改善
- [ ] パフォーマンス最適化
- [ ] ログ集約システム導入

---

## 6. 成功指標（KPI）

### セキュリティ
- [ ] ハードコーディングされた認証情報: 0件
- [ ] NetworkPolicy適用率: 100%
- [ ] 非rootコンテナ実行率: 100%

### 運用安定性
- [ ] リソース制限設定率: 100%
- [ ] 平均復旧時間（MTTR）: < 30分
- [ ] バックアップ成功率: > 99%

### 品質
- [ ] テストカバレッジ: > 80%
- [ ] ドキュメント正確性: 100%
- [ ] CI/CDパイプライン成功率: > 95%

---

## 7. リスクと対策

### リスク1: 変更による既存環境への影響
**対策**: 
- すべての変更を非本番環境でテスト
- 段階的なロールアウト戦略
- ロールバック手順の文書化

### リスク2: 実装リソース不足
**対策**:
- 優先度に基づく段階的実装
- 自動化ツールの活用
- 外部リソースの活用検討

---

## 8. まとめ

k8s_myHomeプロジェクトは基本的によく設計されていますが、本番環境での運用を想定した場合、特にセキュリティと運用安定性の面で改善が必要です。本計画書に従って段階的に改善を実施することで、より堅牢で保守しやすいKubernetesインフラストラクチャを実現できます。

### 次のステップ
1. Critical項目の即座実施
2. 改善実施体制の確立
3. 進捗の週次レビュー
4. KPI測定と継続的改善

---

## 付録A: 改善実装チェックリスト

```markdown
## Critical (今すぐ)
- [ ] settings.toml.exampleから認証情報削除
- [ ] .env.exampleファイル作成
- [ ] NetworkPolicy YAML作成
- [ ] NetworkPolicy適用

## High (1週間以内)
- [ ] リソース制限スクリプト作成
- [ ] 全アプリケーションにリソース制限適用
- [ ] SecurityContext設定追加
- [ ] Prometheus Stack導入
- [ ] Veleroバックアップ設定

## Medium (1ヶ月以内)
- [ ] CLAUDE.md更新
- [ ] 重複ファイル削除
- [ ] retry-helper.sh作成
- [ ] CI/CDパイプライン構築

## Low (計画的)
- [ ] VM起動並列化
- [ ] ELKスタック導入
```

---

## 付録B: 緊急時対応手順

### セキュリティインシデント発生時
1. 影響範囲の特定
2. 該当サービスの隔離
3. ログの保全
4. 原因調査
5. 修正適用
6. 再発防止策の実装

### サービス障害時
1. 障害サービスの特定
2. ロールバック判断
3. 復旧作業実施
4. 動作確認
5. 原因分析
6. 改善策の実装

---

**文書バージョン**: 1.0.0  
**作成日**: 2025-01-23  
**次回レビュー**: 2025-02-23