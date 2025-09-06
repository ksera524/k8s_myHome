# 即座に実施可能な改善項目

## 🚨 現在の具体的な問題点と改善提案

### 1. エラーハンドリングの不備

#### 問題箇所
```bash
# automation/platform/platform-deploy.sh (Line 60-65)
if ! ssh -T -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
    print_error "k8sクラスタに接続できません"
    exit 1
fi
```

#### 改善案
```bash
# エラー時の詳細情報を追加
if ! ssh -T -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get nodes' >/dev/null 2>&1; then
    print_error "k8sクラスタに接続できません"
    print_error "確認事項:"
    print_error "  1. VMが起動しているか: virsh list --all"
    print_error "  2. SSHサービスが起動しているか: systemctl status sshd"
    print_error "  3. kubeletが正常か: ssh k8suser@192.168.122.10 'systemctl status kubelet'"
    print_error "詳細ログ: $LOG_FILE"
    exit 1
fi
```

### 2. ハードコードされた値

#### 問題箇所 (29ファイル中15ファイルで発見)
- IPアドレス: `192.168.122.10`, `192.168.122.100`
- ユーザー名: `k8suser`
- タイムアウト値: `300s`, `120s`

#### 改善案
```bash
# automation/config/environment.conf
readonly K8S_CONTROL_PLANE_IP="192.168.122.10"
readonly K8S_WORKER1_IP="192.168.122.11"
readonly K8S_WORKER2_IP="192.168.122.12"
readonly HARBOR_IP="192.168.122.100"
readonly K8S_USER="k8suser"
readonly DEFAULT_TIMEOUT="300s"
readonly RETRY_COUNT=3
readonly RETRY_DELAY=5

# 使用例
source automation/config/environment.conf
ssh -o StrictHostKeyChecking=no ${K8S_USER}@${K8S_CONTROL_PLANE_IP}
```

### 3. ログ出力の一貫性欠如

#### 現状の問題
- `echo`、`print_status`、`print_error`が混在
- タイムスタンプなし
- ログレベル不明確

#### 改善案
```bash
# automation/lib/logger.sh
#!/bin/bash

readonly LOG_DIR="/var/log/k8s-myhome"
readonly LOG_FILE="${LOG_DIR}/$(date +%Y%m%d).log"

# ログレベル定義
readonly LOG_LEVEL_ERROR=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_INFO=3
readonly LOG_LEVEL_DEBUG=4

log() {
    local level=$1
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="[$timestamp] [$level] $*"
    
    # 標準出力とファイルの両方に出力
    echo "$message" | tee -a "$LOG_FILE"
    
    # Syslogにも送信
    logger -t "k8s-myhome" -p "local0.$level" "$*"
}

log_error() { log "ERROR" "$@"; }
log_warn()  { log "WARN"  "$@"; }
log_info()  { log "INFO"  "$@"; }
log_debug() { [[ $DEBUG ]] && log "DEBUG" "$@"; }
```

### 4. 依存関係の暗黙的な前提

#### 問題
- スクリプト間の依存関係が不明確
- 必要なツールの事前チェックなし

#### 改善案
```bash
# automation/lib/dependencies.sh
#!/bin/bash

check_dependencies() {
    local deps=("kubectl" "terraform" "ansible" "jq" "yq" "helm")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing dependencies: ${missing[*]}"
        echo "Install with: apt-get install ${missing[*]}"
        return 1
    fi
    
    return 0
}

check_cluster_state() {
    # クラスタの状態確認
    local required_nodes=3
    local ready_nodes=$(kubectl get nodes --no-headers | grep -c Ready)
    
    if [[ $ready_nodes -lt $required_nodes ]]; then
        echo "Cluster not ready: $ready_nodes/$required_nodes nodes ready"
        return 1
    fi
    
    return 0
}
```

### 5. テストの完全欠如

#### 即座に追加可能なテスト

##### スモークテスト
```bash
#!/bin/bash
# test/smoke/basic-connectivity.sh

set -euo pipefail

echo "=== Basic Connectivity Test ==="

# 1. VM接続テスト
for ip in 192.168.122.10 192.168.122.11 192.168.122.12; do
    if ping -c 1 -W 1 $ip &>/dev/null; then
        echo "✓ $ip: reachable"
    else
        echo "✗ $ip: unreachable"
        exit 1
    fi
done

# 2. Kubernetes API テスト
if kubectl cluster-info &>/dev/null; then
    echo "✓ Kubernetes API: accessible"
else
    echo "✗ Kubernetes API: not accessible"
    exit 1
fi

# 3. 基本的なポッド起動テスト
kubectl run test-pod --image=busybox --restart=Never -- echo "Hello"
kubectl wait --for=condition=Completed pod/test-pod --timeout=30s
kubectl delete pod test-pod

echo "=== All smoke tests passed ==="
```

##### バリデーションテスト
```bash
#!/bin/bash
# test/validation/manifest-check.sh

set -euo pipefail

echo "=== Manifest Validation ==="

# YAMLシンタックスチェック
for file in manifests/**/*.yaml; do
    if yq eval '.' "$file" > /dev/null 2>&1; then
        echo "✓ $file: valid YAML"
    else
        echo "✗ $file: invalid YAML"
        exit 1
    fi
done

# Kubernetesマニフェスト検証
for file in manifests/**/*.yaml; do
    if kubectl apply --dry-run=client -f "$file" > /dev/null 2>&1; then
        echo "✓ $file: valid Kubernetes manifest"
    else
        echo "✗ $file: invalid Kubernetes manifest"
        exit 1
    fi
done

echo "=== All validations passed ==="
```

## ✅ 今すぐ実施すべきアクション (優先度順)

### Priority 1: Critical (今日中)
- [ ] **バックアップ作成**: 現在の動作環境の完全バックアップ
  ```bash
  tar -czf k8s-myhome-backup-$(date +%Y%m%d).tar.gz \
    --exclude='.git' --exclude='*.log' /home/ksera/k8s_myHome
  ```

- [ ] **エラーハンドリング追加**: 全スクリプトに`set -euo pipefail`を追加
  ```bash
  find automation -name "*.sh" -exec sed -i '2i\set -euo pipefail' {} \;
  ```

- [ ] **ログディレクトリ作成**:
  ```bash
  sudo mkdir -p /var/log/k8s-myhome
  sudo chown $USER:$USER /var/log/k8s-myhome
  ```

### Priority 2: High (今週中)
- [ ] **設定ファイル統合**: 
  ```bash
  cat > automation/config/defaults.conf << 'EOF'
  # Default configuration
  export K8S_CLUSTER_NAME="${K8S_CLUSTER_NAME:-home-k8s}"
  export K8S_NETWORK="${K8S_NETWORK:-192.168.122.0/24}"
  export LOG_LEVEL="${LOG_LEVEL:-INFO}"
  export BACKUP_DIR="${BACKUP_DIR:-/var/backups/k8s-myhome}"
  EOF
  ```

- [ ] **README.md更新**: インストール手順、トラブルシューティング追加

- [ ] **依存関係チェッカー作成**:
  ```bash
  automation/scripts/check-requirements.sh
  ```

### Priority 3: Medium (今月中)
- [ ] **CI/CD パイプライン**: GitHub Actions設定
- [ ] **監視ダッシュボード**: Grafanaダッシュボード作成
- [ ] **自動バックアップ**: CronJobでの定期バックアップ

### Priority 4: Low (3ヶ月以内)
- [ ] **Helm Chart化**: 全コンポーネントのHelm Chart作成
- [ ] **マルチ環境対応**: dev/staging/prod環境の分離
- [ ] **完全自動リカバリ**: 障害時の自動復旧機能

## 📋 日次チェックリスト

```bash
#!/bin/bash
# daily-check.sh

echo "=== Daily Health Check $(date) ==="

# 1. クラスタ状態
echo -n "Cluster nodes: "
kubectl get nodes --no-headers | grep -c Ready

# 2. Pod状態
echo -n "Failed pods: "
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed | wc -l

# 3. ディスク使用率
echo "Disk usage:"
df -h | grep -E '(/$|/var)'

# 4. メモリ使用率
echo "Memory usage:"
free -h

# 5. 証明書有効期限
echo "Certificate expiry:"
kubectl get cert --all-namespaces -o json | \
  jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name): \(.status.notAfter)"'

# 6. 最新のエラーログ
echo "Recent errors (last 10):"
journalctl -u kubelet --since "1 hour ago" | grep -i error | tail -10

echo "=== Check completed ==="
```

## 🔧 デバッグ用ユーティリティ

```bash
# automation/scripts/debug-helper.sh
#!/bin/bash

debug_pod() {
    local namespace=$1
    local pod=$2
    
    echo "=== Pod Debug Info: $namespace/$pod ==="
    kubectl describe pod -n "$namespace" "$pod"
    echo "=== Recent logs ==="
    kubectl logs -n "$namespace" "$pod" --tail=50
    echo "=== Previous logs (if crashed) ==="
    kubectl logs -n "$namespace" "$pod" --previous --tail=50 2>/dev/null || echo "No previous logs"
}

debug_deployment() {
    local namespace=$1
    local deployment=$2
    
    echo "=== Deployment Debug Info: $namespace/$deployment ==="
    kubectl describe deployment -n "$namespace" "$deployment"
    kubectl get rs -n "$namespace" -l app="$deployment"
    kubectl get pods -n "$namespace" -l app="$deployment"
}

debug_service() {
    local namespace=$1
    local service=$2
    
    echo "=== Service Debug Info: $namespace/$service ==="
    kubectl describe service -n "$namespace" "$service"
    kubectl get endpoints -n "$namespace" "$service"
}

# 使用例
# ./debug-helper.sh pod default my-app
# ./debug-helper.sh deployment harbor harbor-core
# ./debug-helper.sh service ingress-nginx ingress-nginx-controller
```

## 📊 改善効果の測定

### KPI定義
| メトリクス | 現在値 | 目標値 | 測定方法 |
|-----------|--------|--------|----------|
| デプロイ成功率 | 不明 | 95%+ | CI/CDメトリクス |
| 平均復旧時間 (MTTR) | 不明 | <30分 | インシデントログ |
| コードカバレッジ | 0% | 80%+ | テストツール |
| ドキュメント完成度 | 20% | 100% | ドキュメント監査 |
| 自動化率 | 70% | 95%+ | 手動タスク削減率 |

### 週次レポートテンプレート
```markdown
# 週次保守レポート - Week of [DATE]

## 実施項目
- [ ] 項目1
- [ ] 項目2

## 発見された問題
- 問題1: [詳細]
  - 影響: [影響範囲]
  - 対応: [対応内容]

## 改善提案
- 提案1: [内容]
  - 効果: [期待効果]
  - 工数: [必要工数]

## 次週の計画
- [ ] タスク1
- [ ] タスク2

## メトリクス
- デプロイ回数: X回
- 障害発生: Y件
- 改善実施: Z件
```

---

作成日: 2025-01-07
最終更新: 2025-01-07
レビュー予定: 2025-01-14