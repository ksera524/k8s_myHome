# settings.toml ハードコード値移行レポート

## 📋 概要

すべてのハードコードされた値を`settings.toml`に移行しました。秘匿する必要のない値は`settings.toml.example`にデフォルト値として記載しています。

## 🔄 移行済み設定値

### ネットワーク設定
| 設定項目 | セクション.キー | デフォルト値 | 使用箇所 |
|---------|---------------|------------|---------|
| ホストネットワーク | `network.network_cidr` | `192.168.122.0/24` | VM設定 |
| ゲートウェイ | `network.gateway_ip` | `192.168.122.1` | ネットワーク設定 |
| Control Plane IP | `network.control_plane_ip` | `192.168.122.10` | SSH接続、kubectl |
| Worker 1 IP | `network.worker_1_ip` | `192.168.122.11` | SSH接続 |
| Worker 2 IP | `network.worker_2_ip` | `192.168.122.12` | SSH接続 |
| Harbor IP | `network.harbor_lb_ip` | `192.168.122.100` | レジストリアクセス |
| Ingress IP | `network.ingress_lb_ip` | `192.168.122.101` | Ingress設定 |
| ArgoCD IP | `network.argocd_lb_ip` | `192.168.122.102` | ArgoCD設定 |

### Kubernetes設定
| 設定項目 | セクション.キー | デフォルト値 | 使用箇所 |
|---------|---------------|------------|---------|
| クラスタ名 | `kubernetes.cluster_name` | `home-k8s` | クラスタ識別 |
| Kubernetesバージョン | `kubernetes.version` | `v1.29.0` | インストール |
| ユーザー | `kubernetes.user` | `k8suser` | SSH接続 |
| SSHキー | `kubernetes.ssh_key_path` | `/home/k8suser/.ssh/id_ed25519` | SSH認証 |

### アプリケーションバージョン
| 設定項目 | セクション.キー | デフォルト値 | 使用箇所 |
|---------|---------------|------------|---------|
| MetalLB | `versions.metallb` | `0.13.12` | Helm Chart |
| NGINX Ingress | `versions.ingress_nginx` | `4.8.2` | Helm Chart |
| cert-manager | `versions.cert_manager` | `1.13.3` | Helm Chart |
| ArgoCD | `versions.argocd` | `5.51.6` | Helm Chart |
| Harbor | `versions.harbor` | `1.13.1` | Helm Chart |
| External Secrets | `versions.external_secrets` | `0.9.11` | Helm Chart |

### タイムアウト設定
| 設定項目 | セクション.キー | デフォルト値 | 使用箇所 |
|---------|---------------|------------|---------|
| デフォルト | `timeout.default` | `300` | 汎用タイムアウト |
| kubectl | `timeout.kubectl` | `120` | kubectlコマンド |
| Helm | `timeout.helm` | `300` | Helmコマンド |
| ArgoCD同期 | `timeout.argocd_sync` | `600` | ArgoCD同期待機 |
| Terraform | `timeout.terraform` | `600` | Terraform実行 |

## 🔧 更新されたファイル

### 1. `automation/settings.toml.example`
- すべてのハードコード値をデフォルト値として追加
- 秘匿不要な値は直接記載
- セクション構造を整理

### 2. `automation/scripts/settings-loader.sh`
- 拡張版TOMLパーサー実装
- 環境変数マッピング強化
- `get_config()`関数追加
- `has_config()`関数追加

### 3. `automation/platform/platform-deploy.sh`
- ハードコードIPアドレスを変数参照に変更
- settings.tomlから自動読み込み
- デフォルト値付きで後方互換性維持

### 4. `automation/scripts/common-ssh.sh`
- settings-loader.sh自動読み込み追加
- IP設定を環境変数から取得

### 5. `automation/makefiles/variables.mk`
- settings.toml自動読み込み追加
- Make変数に`?=`演算子使用でデフォルト値設定

## 📝 使用方法

### 基本的な使用
```bash
# settings.tomlを作成（初回のみ）
cp automation/settings.toml.example automation/settings.toml

# 必要に応じて値を編集
vim automation/settings.toml

# make allで自動的に読み込まれる
make all
```

### スクリプトでの使用
```bash
#!/bin/bash
# settings-loader.shを読み込み
source "$(dirname "$0")/../scripts/settings-loader.sh" load

# 環境変数として利用可能
echo "Control Plane: $K8S_CONTROL_PLANE_IP"
echo "Harbor IP: $HARBOR_IP"

# get_config関数での取得
CLUSTER_NAME=$(get_config kubernetes cluster_name)
echo "Cluster: $CLUSTER_NAME"
```

### Makefileでの使用
```makefile
# variables.mkで自動読み込み済み
ssh-control:
	ssh $(SSH_OPTS) $(K8S_USER)@$(K8S_CONTROL_PLANE_IP)
```

## ✅ 利点

1. **一元管理**: すべての設定が`settings.toml`に集約
2. **可読性**: セクション構造で整理された設定
3. **保守性**: ハードコード削減により変更が容易
4. **互換性**: デフォルト値により既存スクリプトとの互換性維持
5. **安全性**: `.gitignore`登録済みで秘密情報保護

## 🚀 今後の改善案

1. **検証機能追加**
   - 必須設定の存在確認
   - IP形式の妥当性検証
   - ポート番号範囲チェック

2. **環境別設定**
   - development/staging/production設定の切り替え
   - プロファイル機能の実装

3. **設定の暗号化**
   - 機密情報の暗号化保存
   - External Secrets完全統合

---

作成日: 2025-01-26
実装完了: ハードコード値のsettings.toml移行