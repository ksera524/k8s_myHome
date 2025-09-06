# settings.toml 統一設定ガイド

## 🎯 概要

`environment.conf`を廃止し、全ての設定を`settings.toml`に統一することで、設定管理を簡素化します。

## 📋 現状分析

### 既存の設定管理
- **settings.toml**: Pulumi、GitHub、ネットワーク設定など
- **settings-loader.sh**: TOMLパーサー機能実装済み
- **提案されたenvironment.conf**: ハードコード値の集約（未実装）

### settings.tomlの利点
1. **既存インフラ**: `settings-loader.sh`にTOMLパーサー実装済み
2. **統一管理**: 1つのファイルで全設定を管理
3. **構造化**: セクション分けで整理された設定
4. **Git除外**: 既に`.gitignore`に追加済み

## 🔧 拡張版 settings.toml

```toml
# k8s_myHome 統一設定ファイル
# このファイルをコピーして settings.toml として使用してください

# ========================================
# 基本設定
# ========================================
[project]
cluster_name = "home-k8s"
environment = "production"  # development, staging, production
debug = false
verbose = true

# ========================================
# ホストセットアップ
# ========================================
[host_setup]
# USB外部ストレージデバイス名
usb_device_name = ""
storage_base = "/data"
nfs_share = "/data/nfs-share"
local_volumes = "/data/local-volumes"

# ========================================
# Kubernetes設定
# ========================================
[kubernetes]
# APT鍵ファイル上書き確認
overwrite_kubernetes_keyring = "y"
# バージョン設定
version = "v1.29.0"
pod_network_cidr = "10.244.0.0/16"
service_cidr = "10.96.0.0/12"
# ユーザー設定
user = "k8suser"
user_home = "/home/k8suser"
ssh_key = "/home/k8suser/.ssh/id_ed25519"

# ========================================
# ネットワーク設定
# ========================================
[network]
# ホストネットワーク
host_network_cidr = "192.168.122.0/24"
host_gateway_ip = "192.168.122.1"

# Kubernetes クラスタノード
control_plane_ip = "192.168.122.10"
worker_1_ip = "192.168.122.11"
worker_2_ip = "192.168.122.12"

# MetalLB LoadBalancer IP範囲
metallb_ip_start = "192.168.122.100"
metallb_ip_end = "192.168.122.150"

# サービス固定IP
harbor_lb_ip = "192.168.122.100"
ingress_lb_ip = "192.168.122.101"
argocd_lb_ip = "192.168.122.102"

# ポート設定
kubernetes_api_port = 6443
argocd_port_forward = 8080
harbor_port_forward = 8081

# ========================================
# タイムアウト設定
# ========================================
[timeout]
default = "300s"
kubectl = "120s"
helm = "300s"
argocd_sync = "600s"
terraform = "600s"

# ========================================
# リトライ設定
# ========================================
[retry]
default_count = 3
default_delay = 5
max_delay = 60

# ========================================
# アプリケーションバージョン
# ========================================
[versions]
metallb = "0.13.12"
ingress_nginx = "4.8.2"
cert_manager = "1.13.3"
argocd = "5.51.6"
harbor = "1.13.1"
flannel = "latest"

# ========================================
# Harbor設定
# ========================================
[harbor]
admin_password = "Harbor12345"
project = "sandbox"
url = "harbor.local"
registry_size = "100Gi"
database_size = "10Gi"

# ========================================
# Pulumi設定
# ========================================
[pulumi]
# Pulumi Access Token (必須)
# 取得方法: https://app.pulumi.com/account/tokens
access_token = ""
organization = ""
backend_url = ""  # オプション: カスタムバックエンド

# ========================================
# GitHub設定
# ========================================
[github]
# Personal Access Token
personal_access_token = ""
# リポジトリ (例: username/repository)
repository = ""
# ユーザー名（ArgoCD OAuth用）
username = ""

# GitHub Actions Runner Controller (ARC) 設定
arc_repositories = [
    # [リポジトリ名, 最小Runner数, 最大Runner数, 説明]
    # ["k8s_myHome", 1, 3, "メインプロジェクト"],
]

# ========================================
# ログ設定
# ========================================
[logging]
# ログディレクトリ
log_dir = "/var/log/k8s-myhome"
# ログレベル: ERROR, WARN, INFO, DEBUG
log_level = "INFO"
# ログローテーション
max_log_size = "100M"
max_log_files = 10
# syslog転送
enable_syslog = false
syslog_server = ""

# ========================================
# 自動化オプション
# ========================================
[automation]
auto_confirm_overwrite = true
enable_external_secrets = true
enable_github_actions = true
enable_monitoring = true
enable_backup = true

# バックアップ設定
backup_dir = "/var/backups/k8s-myhome"
backup_retention_days = 30

# ========================================
# モニタリング設定
# ========================================
[monitoring]
enable_prometheus = true
enable_grafana = true
enable_alertmanager = true
prometheus_retention = "30d"
prometheus_storage = "50Gi"
grafana_admin_password = ""  # 空の場合は自動生成

# ========================================
# セキュリティ設定
# ========================================
[security]
enable_network_policies = true
enable_pod_security_policies = true
enable_audit_logging = true
certificate_validity_days = 365
```

## 📝 改良版 settings-loader.sh

```bash
#!/bin/bash
set -euo pipefail

# TOMLファイルを完全にパースして環境変数に変換
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_FILE="${SETTINGS_FILE:-$SCRIPT_DIR/../settings.toml}"

# 改良版TOMLパーサー
parse_toml_advanced() {
    local file="$1"
    local section=""
    
    while IFS= read -r line; do
        # コメントと空行をスキップ
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # セクション検出
        if [[ "$line" =~ ^\[([^\]]+)\] ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi
        
        # キー=値のパース
        if [[ "$line" =~ ^[[:space:]]*([^=]+)[[:space:]]*=[[:space:]]*(.*) ]]; then
            local key="${BASH_REMATCH[1]// /}"
            local value="${BASH_REMATCH[2]}"
            
            # 値のクリーンアップ
            value="${value#\"}"  # 先頭の"を削除
            value="${value%\"}"  # 末尾の"を削除
            value="${value#\'}"  # 先頭の'を削除
            value="${value%\'}"  # 末尾の'を削除
            
            # 環境変数名の生成
            local env_name="CFG_${section^^}_${key^^}"
            export "$env_name=$value"
            
            # 特別なマッピング（後方互換性）
            case "${section}_${key}" in
                "pulumi_access_token")
                    export PULUMI_ACCESS_TOKEN="$value"
                    ;;
                "github_personal_access_token")
                    export GITHUB_TOKEN="$value"
                    ;;
                "github_username")
                    export GITHUB_USERNAME="$value"
                    ;;
                "network_control_plane_ip")
                    export K8S_CONTROL_PLANE_IP="$value"
                    ;;
                "network_harbor_lb_ip")
                    export HARBOR_IP="$value"
                    ;;
                "kubernetes_user")
                    export K8S_USER="$value"
                    ;;
            esac
        fi
    done < "$file"
}

# 設定値取得関数
get_config() {
    local section="$1"
    local key="$2"
    local default="${3:-}"
    
    local env_name="CFG_${section^^}_${key^^}"
    echo "${!env_name:-$default}"
}

# 設定値の存在確認
has_config() {
    local section="$1"
    local key="$2"
    
    local env_name="CFG_${section^^}_${key^^}"
    [[ -n "${!env_name:-}" ]]
}

# 必須設定のチェック
check_required_configs() {
    local missing=()
    
    # 必須設定リスト
    local required_configs=(
        "kubernetes:user"
        "network:control_plane_ip"
        "network:worker_1_ip"
        "network:worker_2_ip"
    )
    
    for config in "${required_configs[@]}"; do
        IFS=':' read -r section key <<< "$config"
        if ! has_config "$section" "$key"; then
            missing+=("[$section] $key")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "❌ 必須設定が不足しています:"
        for item in "${missing[@]}"; do
            echo "  - $item"
        done
        return 1
    fi
    
    return 0
}

# 設定の読み込みとエクスポート
load_settings() {
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        echo "⚠️  設定ファイルが見つかりません: $SETTINGS_FILE"
        echo "   automation/settings.toml.example をコピーして作成してください"
        return 1
    fi
    
    echo "📋 設定ファイル読み込み中: $SETTINGS_FILE"
    parse_toml_advanced "$SETTINGS_FILE"
    
    if check_required_configs; then
        echo "✅ 設定ファイル読み込み完了"
        return 0
    else
        return 1
    fi
}

# メイン処理
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    load_settings
else
    # sourceされた場合は自動的に読み込み
    load_settings >/dev/null 2>&1 || true
fi
```

## 🔄 既存スクリプトの移行

### Before (environment.conf使用)
```bash
#!/bin/bash
source "$(dirname "$0")/../config/environment.conf"

echo "Control Plane IP: $K8S_CONTROL_PLANE_IP"
echo "Harbor IP: $HARBOR_IP"
```

### After (settings.toml使用)
```bash
#!/bin/bash
source "$(dirname "$0")/../scripts/settings-loader.sh"

# 方法1: 環境変数経由
echo "Control Plane IP: $K8S_CONTROL_PLANE_IP"
echo "Harbor IP: $HARBOR_IP"

# 方法2: get_config関数経由
echo "Control Plane IP: $(get_config network control_plane_ip)"
echo "Harbor IP: $(get_config network harbor_lb_ip)"

# 方法3: 直接環境変数
echo "Control Plane IP: $CFG_NETWORK_CONTROL_PLANE_IP"
echo "Harbor IP: $CFG_NETWORK_HARBOR_LB_IP"
```

## 📊 移行計画

### ステップ1: settings.toml拡張 (10分)
```bash
# 1. 既存のsettings.tomlをバックアップ
cp automation/settings.toml automation/settings.toml.backup

# 2. 拡張版に更新
vim automation/settings.toml
# 上記の拡張版設定を追加

# 3. settings-loader.sh更新
vim automation/scripts/settings-loader.sh
# 改良版パーサーに更新
```

### ステップ2: スクリプト更新 (20分)
```bash
# 全スクリプトでsettings-loader.shを使用するよう更新
for script in automation/**/*.sh; do
    # environment.confの参照を削除
    sed -i '/source.*environment\.conf/d' "$script"
    
    # settings-loader.shを追加（まだない場合）
    if ! grep -q "settings-loader.sh" "$script"; then
        sed -i '7i\source "$(dirname "$0")/../scripts/settings-loader.sh"' "$script"
    fi
done
```

### ステップ3: 検証 (10分)
```bash
# 設定テスト
source automation/scripts/settings-loader.sh
echo "K8S_CONTROL_PLANE_IP: $K8S_CONTROL_PLANE_IP"
echo "HARBOR_IP: $HARBOR_IP"
echo "K8S_USER: $K8S_USER"

# 全設定の確認
env | grep ^CFG_ | sort
```

## ✅ メリット

1. **一元管理**: 全設定が`settings.toml`に集約
2. **構造化**: セクション分けで整理
3. **既存互換**: 既存の環境変数名を維持
4. **柔軟性**: `get_config`関数で動的アクセス
5. **バリデーション**: 必須設定の自動チェック
6. **Git安全**: 既に`.gitignore`に登録済み

## 🚀 使用例

### Makefile統合
```makefile
# 設定読み込み
include automation/makefiles/functions.mk

# settings.tomlから値を取得
setup: 
	@source automation/scripts/settings-loader.sh && \
	echo "Cluster: $$CFG_PROJECT_CLUSTER_NAME" && \
	echo "Environment: $$CFG_PROJECT_ENVIRONMENT"
```

### CI/CD統合
```yaml
# GitHub Actions
- name: Load configuration
  run: |
    source automation/scripts/settings-loader.sh
    echo "CLUSTER=$CFG_PROJECT_CLUSTER_NAME" >> $GITHUB_ENV
```

### Python統合
```python
import tomli
import os

# settings.toml読み込み
with open("automation/settings.toml", "rb") as f:
    config = tomli.load(f)

# 環境変数として設定
for section, values in config.items():
    for key, value in values.items():
        env_name = f"CFG_{section.upper()}_{key.upper()}"
        os.environ[env_name] = str(value)
```

## 📝 注意事項

1. **移行時の確認**
   - 既存の`settings.toml`をバックアップ
   - 段階的に移行（スクリプトごと）
   - 動作確認を都度実施

2. **命名規則**
   - 環境変数: `CFG_<SECTION>_<KEY>`
   - 後方互換: 主要変数は従来名も維持

3. **セキュリティ**
   - `settings.toml`のパーミッション: 600
   - Gitには絶対にコミットしない
   - CI/CDではSecrets経由で注入

---

作成日: 2025-01-26
実装予定: 即座に実施可能
推定所要時間: 40分