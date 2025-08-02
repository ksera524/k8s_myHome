# make all 詳細実行ステップドキュメント

このドキュメントは `automation/Makefile` の `make all` コマンドで実行される全自動デプロイの詳細なステップを解説します。

## 概要

`make all` は k8s_myHome プロジェクトの完全自動デプロイを実行します。以下の4つの主要フェーズと追加の後処理から構成されています：

```bash
make all = check-automation-readiness + host-setup + infrastructure + platform + post-deployment
```

## 実行フロー詳細

### Phase 0: 事前チェック (`check-automation-readiness`)

**実行内容：**
- rootユーザーでの実行を禁止
- プロジェクトルートディレクトリの存在確認
- 実行環境の整合性チェック

**処理時間：** 約5秒

### Phase 1: ホストマシンセットアップ (`host-setup`)

**実行スクリプト：** `automation/host-setup/setup-host.sh`

**詳細ステップ：**

1. **システム更新**
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

2. **仮想化パッケージインストール**
   - qemu-kvm
   - libvirt-daemon-system
   - libvirt-clients
   - bridge-utils
   - virtinst
   - virt-manager
   - virt-viewer
   - cpu-checker

3. **追加ツールインストール**
   - curl, wget, git
   - terraform
   - kubectl
   - ssh関連パッケージ

4. **ユーザー権限設定**
   - libvirtグループへの追加
   - 権限確認と再適用

5. **ストレージ設定** (`setup-storage.sh`)
   - LVMストレージプール作成
   - libvirt用ストレージ設定

6. **セットアップ検証** (`verify-setup.sh`)
   - 仮想化機能の確認
   - 必要コマンドの動作確認

**処理時間：** 約10-15分（初回実行時）

### Phase 2: インフラストラクチャ構築 (`infrastructure`)

**実行スクリプト：** `automation/infrastructure/clean-and-deploy.sh`

**詳細ステップ：**

1. **完全クリーンアップ**
   - 既存k8s VM全削除
   - libvirt関連ファイル削除
   - ストレージクリーンアップ

2. **Terraform初期化**
   ```bash
   terraform init
   terraform plan -out=tfplan
   ```

3. **VM作成（3台）**
   - k8s-control-plane (192.168.122.10)
   - k8s-worker-1 (192.168.122.11)  
   - k8s-worker-2 (192.168.122.12)

4. **VM仕様**
   - Control Plane: 4 CPU, 8GB RAM, 50GB disk
   - Worker Nodes: 2 CPU, 4GB RAM, 30GB disk
   - OS: Ubuntu 24.04 LTS

5. **Kubernetesクラスタ構築**
   - kubeadm初期化（Control Plane）
   - Flannel CNI展開
   - Worker Node参加

6. **クラスタ準備完了待機** (`wait-for-k8s-cluster`)
   - 最大300秒待機
   - 3台全てのNodeがReady状態になるまで監視

**処理時間：** 約20-25分

### Phase 3: プラットフォーム構築 (`platform`)

**実行スクリプト：** `automation/platform/phase4-deploy.sh` (k8s-infrastructure-deploy.sh)

**詳細ステップ：**

#### 3.1 基盤インフラ構築

1. **MetalLB LoadBalancer**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
   ```
   - IPプール: 192.168.122.100-150

2. **NGINX Ingress Controller**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
   ```

3. **cert-manager**
   ```bash
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
   ```
   - Self-signed ClusterIssuer作成

4. **StorageClass設定**
   - Local StorageClass作成

#### 3.2 GitOps・シークレット管理

5. **ArgoCD**
   ```bash
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   ```
   - insecureモード設定
   - Ingress設定

6. **External Secrets Operator**
   - Helmでのデプロイ
   - Pulumi ESC連携設定
   - 各namespace用Secret作成

#### 3.3 Harbor・認証設定

7. **Harbor管理者パスワード設定**
   - External Secrets経由でPulumi ESCから取得
   - フォールバック：手動パスワード管理

8. **App-of-Apps デプロイ**
   ```bash
   kubectl apply -f app-of-apps.yaml
   ```

9. **GitHub Actions Runner Controller (ARC)**
   - GitHub認証情報の対話式入力
   - Harbor認証情報設定
   - ARC Scale Set展開

10. **Cloudflared設定**
    - External Secrets経由でトークン取得
    - フォールバック：手動トークン入力

#### 3.4 追加設定・修正

11. **Harbor sandboxプロジェクト作成**
    - Harbor API経由でプライベートリポジトリ作成

12. **Kubernetes sandboxネームスペース作成**

13. **Slack Secret作成**
    - External Secrets経由

14. **Harbor証明書修正**
    - IP SAN対応証明書作成
    - CA信頼配布DaemonSet
    - Worker nodeのinsecure registry設定

15. **ArgoCD GitHub OAuth設定**
    - Client Secret設定
    - Dexサーバー再起動

**External Secrets待機** (`wait-for-external-secrets`)
- GitHub External Secret
- Slack External Secret  
- ArgoCD GitHub OAuth External Secret
- Cloudflared External Secret
- 最大180秒待機

**処理時間：** 約30-40分

### Phase 4: ポストデプロイメント

**実行内容：**

1. **GitOps同期待機**
   ```bash
   sleep 15  # GitOps同期待機延長
   ```

2. **External Secrets強制同期**
   ```bash
   kubectl patch application applications -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
   ```

3. **Cloudflaredアプリケーション確認**
   - ArgoCD App-of-Apps経由での確認
   - 手動作成は行わない（GitOpsアプローチ）

4. **ArgoCD GitHub OAuth最終設定**
   ```bash
   ./setup-argocd-github-oauth.sh
   ```

5. **システム状態確認** (`make status`)
   - VM状態確認
   - Kubernetesクラスタ状態
   - ArgoCD Applications状態
   - LoadBalancer IP確認
   - External Secrets状態確認

**処理時間：** 約5-10分

## 合計実行時間

**初回実行：** 約70-90分  
**再実行：** 約40-60分（パッケージキャッシュ有効時）

## 重要な前提条件

1. **実行環境**
   - Ubuntu 24.04 LTS
   - 非rootユーザーでの実行
   - 十分なディスク容量（100GB以上推奨）

2. **必要なトークン**
   - GitHub Personal Access Token
   - Pulumi Access Token（推奨）
   - Cloudflare Tunnel Token（オプション）

3. **ネットワーク**
   - インターネット接続必須
   - libvirtデフォルトネットワーク（192.168.122.0/24）

## トラブルシューティング

### よくあるエラーと対処法

1. **libvirtグループ権限エラー**
   ```bash
   newgrp libvirt  # 手動でグループ権限を再適用
   ```

2. **External Secrets同期タイムアウト**
   - Pulumi Access Tokenの確認
   - ネットワーク接続確認
   - 手動でExternalSecretの状態確認

3. **Harbor証明書エラー**
   ```bash
   make harbor-cert-fix  # 証明書修正の手動実行
   ```

4. **ArgoCD OAuth設定エラー**
   - GitHub App設定の確認
   - Client Secret の正確性確認

## 監視・確認コマンド

```bash
# 全体状態確認
make status

# ログ確認
make logs

# 検証実行
make verify

# 開発用情報表示
make dev-info
```

## 成果物

`make all` 完了後、以下が利用可能になります：

- **Kubernetesクラスタ**（3ノード構成）
- **ArgoCD UI**：kubectl port-forward svc/argocd-server -n argocd 8080:443
- **Harbor UI**：kubectl port-forward svc/harbor-core -n harbor 8081:80  
- **GitHub Actions Self-hosted Runner**
- **External Secrets管理**（Pulumi ESC連携）
- **完全なGitOpsワークフロー**

すべてのアプリケーション（RSS、Hitomi、Pepup、Cloudflared、Slack）がArgoCD経由で自動デプロイされ、GitOpsワークフローが確立されます。