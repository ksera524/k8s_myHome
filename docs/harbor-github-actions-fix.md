# Harbor GitHub Actions Integration Fix

## 概要
GitHub Actions RunnerからHarborへのイメージPushで発生していた404エラーを修正。
問題の根本原因は、HarborがIngress経由でのみアクセス可能で、IPアドレス直接アクセスができない設定になっていたこと。

## 修正内容

### 1. Harbor設定の修正

#### ArgoCD Application設定 (`manifests/bootstrap/applications/harbor-app.yaml`)
```yaml
# 変更前
externalURL: http://192.168.122.100

# 変更後  
externalURL: http://harbor.local
```

#### platform-deploy.sh
- Harbor ConfigMapの`EXT_ENDPOINT`を自動的に`http://harbor.local`に修正する処理を追加
- Worker nodeのContainerd設定を`harbor.local`を使用するように変更
- `/etc/hosts`に`harbor.local`エントリを自動追加

### 2. GitHub Actions Runner設定の修正

#### RunnerScaleSet設定 (`manifests/platform/ci-cd/github-actions/multi-repo-runner-scalesets.yaml`)
```yaml
# hostAliasesを追加
spec:
  template:
    spec:
      hostAliases:
      - ip: "192.168.122.100"
        hostnames:
        - "harbor.local"
      
      containers:
      - name: runner
        env:
        - name: HARBOR_URL
          value: "harbor.local"  # IPアドレスからホスト名に変更
```

#### add-runner.sh
- Helm installコマンドにhostAliases設定を追加
- GitHub Actions workflowで`/etc/hosts`にharbor.localを追加
- skopeoコマンドで`harbor.local:80`を使用

### 3. システム全体の動作フロー

```
GitHub Actions Runner
    ↓
/etc/hosts または hostAliases で harbor.local → 192.168.122.100
    ↓  
NGINX Ingress (192.168.122.100:80)
    ↓ Host: harbor.local ヘッダーでルーティング
Harbor Service (harbor-core)
    ↓
Harbor Registry
```

## 適用方法

### 新規環境構築時
```bash
make all
# または
make platform
```
自動的に正しい設定でHarborとGitHub Actions Runnerがデプロイされます。

### 既存環境の修正
```bash
# 1. 最新コードを取得
git pull

# 2. ArgoCD経由でHarbor設定を更新
kubectl -n argocd patch application harbor --type merge -p '{"operation":{"sync":{"prune":true}}}'

# 3. 既存のRunnerを再作成
make add-runner REPO=your-repository
```

## 検証方法

### Harbor APIアクセステスト
```bash
# IPアドレス直接（失敗するはず）
curl http://192.168.122.100/v2/
# → 404 Not Found

# ホスト名指定（成功するはず）
curl -H "Host: harbor.local" http://192.168.122.100/v2/
# → 401 Unauthorized (認証が必要だが、APIは応答)
```

### Runner Pod内でのテスト
```bash
# Runner Podに接続
kubectl exec -it -n arc-systems [runner-pod-name] -c runner -- bash

# hostsファイル確認
cat /etc/hosts | grep harbor
# → 192.168.122.100 harbor.local

# Harbor APIテスト
curl http://harbor.local/v2/
```

## トラブルシューティング

### エラー: "invalid status code from registry 404"
**原因**: HarborのIngressがホスト名ベースのルーティングを使用
**解決**: harbor.localホスト名を使用し、/etc/hostsまたはhostAliasesで解決

### エラー: "Requesting bear token: 404"  
**原因**: Harbor token serviceエンドポイントが見つからない
**解決**: Harbor ConfigMapのEXT_ENDPOINTをharbor.localに設定

### エラー: skopeoでPush失敗
**確認事項**:
1. harbor.localが192.168.122.100に解決されているか
2. ポート80を明示的に指定しているか（`harbor.local:80`）
3. `--dest-tls-verify=false`オプションが設定されているか

## 関連ファイル

- `manifests/bootstrap/applications/harbor-app.yaml` - Harbor ArgoCD Application
- `manifests/platform/ci-cd/github-actions/multi-repo-runner-scalesets.yaml` - RunnerScaleSet設定
- `automation/platform/platform-deploy.sh` - Platform deployment script
- `automation/scripts/github-actions/add-runner.sh` - Runner追加スクリプト

## 今後の改善点

1. **DNS設定**: 将来的にCoreDNSやMetalLB統合DNSを使用してharbor.localを自動解決
2. **HTTPS化**: cert-managerを使用してHTTPS化し、TLS検証を有効化
3. **External DNS**: 外部DNSプロバイダーと統合して実際のドメイン名を使用