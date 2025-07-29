# Kubernetes Manifests Directory

このディレクトリには、automation/platform配下のシェルスクリプトで使用されるKubernetesマニフェストファイルが含まれています。

## ファイル一覧

### 基盤インフラ関連

- **`metallb-ipaddress-pool.yaml`**: MetalLB LoadBalancerのIPアドレスプール設定
  - IPAddressPool: 192.168.122.100-150の範囲を定義
  - L2Advertisement: L2レベルでのアドレス広告設定

- **`cert-manager-selfsigned-issuer.yaml`**: cert-manager用のself-signedクラスタ発行者
  - 開発環境でのTLS証明書自動発行用

- **`local-storage-class.yaml`**: ローカルストレージクラス定義
  - 永続ボリューム用の基本ストレージクラス

### ArgoCD関連

- **`argocd-ingress.yaml`**: ArgoCD WebUI用のIngress設定
  - HTTP接続対応
  - argocd.localドメインでアクセス可能

- **`app-of-apps.yaml`**: ArgoCD App-of-Appsパターンの実装
  - GitOpsでのインフラ全体管理
  - infra/ディレクトリをソースとして使用

### Harbor関連

- **`harbor-http-ingress.yaml`**: Harbor用のHTTP Ingress設定
  - Docker Registry API（/v2/）への直接アクセス対応
  - GitHub Actionsからのpush/pull用

### GitHub Actions関連

- **`github-actions-rbac.yaml`**: GitHub Actions Runner用のRBAC設定  
  - Secretの読み取り権限付与
  - ServiceAccount「github-actions-runner」用

### External Secrets関連

- **`slack-externalsecret.yaml`**: Slack認証情報のExternalSecret設定
  - Pulumi ESCからSlack認証情報を自動取得
  - sandbox namespaceにslack secretを作成

## 使用方法

これらのマニフェストファイルは、automation/platform配下のシェルスクリプトから自動的に参照されます：

1. **k8s-infrastructure-deploy.sh**: メインインフラ構築スクリプト
   - スクリプト実行時に必要なマニフェストをリモートにコピー
   - 埋め込まれたYAMLの代わりにファイル参照方式を使用

2. **setup-arc.sh**: GitHub Actions Runner Controllerセットアップ
   - RBAC設定をマニフェストファイルから適用

3. **harbor-cert-fix.sh**: Harbor証明書修正スクリプト
   - HTTP Ingressをマニフェストファイルから適用

## メリット

- **保守性**: YAMLファイルが独立しているため、個別に編集・テストが可能
- **再利用性**: 複数のスクリプトから同じマニフェストを参照可能
- **バージョン管理**: Gitでの変更追跡が容易
- **検証**: YAMLファイル単体での構文チェックが可能

## 検証方法

```bash
# 全マニフェストの構文チェック
for file in automation/platform/manifests/*.yaml; do
    python3 -c "import yaml; list(yaml.safe_load_all(open('$file')))" && echo "✓ $file: Valid"
done

# 個別ファイルの内容確認
kubectl --dry-run=client apply -f automation/platform/manifests/metallb-ipaddress-pool.yaml
```