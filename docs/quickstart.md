# クイックスタートガイド

> 注記: この文書は current main の最短セットアップ導線を正とします。構造改革で planned target-state にのみ存在する導線や未実装の将来手順は `tasks/` を参照してください。

## 🚀 5分でk8s_myHomeを起動

このガイドでは、k8s_myHome Kubernetesクラスターを最速でセットアップする方法を説明します。

## 前提条件

- Ubuntu 24.04 LTS
- 16GB+ RAM
- 200GB+ ストレージ
- インターネット接続

## 事前ツール確認

CI と同等の検証は Nix toolchain を正規導線にします。ローカルに Nix がない場合は Dockerized Nix の `make validate` を使います。

```bash
make validate
```

Nix を使える環境では、検証ツールと bootstrap 用 CLI を次で揃えます。

```bash
nix develop .#default --command automation/scripts/ci/validate.sh
nix develop .#bootstrap
```

`automation/scripts/ci/validate.sh` の直実行は、`shellcheck`, `yamllint`, `kustomize`, `kubeconform` などが導入済みの場合だけ使います。

## ステップ1: リポジトリ取得

```bash
git clone https://github.com/ksera524/k8s_myHome.git
cd k8s_myHome
```

## ステップ2: 設定ファイル準備

```bash
# 設定ファイルをコピー
cp automation/settings.toml.example automation/settings.toml

# 必須項目を編集
vim automation/settings.toml
```

### 最小限の設定項目:

```toml
[pulumi]
access_token = "pul-xxxxx"  # Pulumiトークン（必須）

[github]
username = "your-username"   # GitHubユーザー名（必須）
```

## ステップ3: 自動デプロイ実行

```bash
make all
```

`make all` は `make phase1 -> make phase2 -> make bootstrap -> make phase5` の順に実行します。

⏱️ **所要時間**: 約30-45分

## ステップ4: 動作確認

```bash
# 確認フェーズ
make phase5

# ノード確認
ssh k8suser@192.168.122.10 'kubectl get nodes'
```

## 🎯 デプロイ完了後

### ArgoCD アクセス

```bash
# 別ターミナルで実行
kubectl port-forward svc/argocd-server -n argocd 8080:443

# ブラウザでアクセス
# URL: https://localhost:8080
# User: admin
# Pass: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Harbor アクセス

```bash
# 別ターミナルで実行
kubectl port-forward svc/harbor-core -n harbor 8081:80

# ブラウザでアクセス（内部）
# URL: https://harbor.internal.qroksera.com
# 直接アクセスできない場合は http://localhost:8081 を使用
# User: admin
# Pass: <harbor-admin-password>（初期値は変更）
```

## 📝 よく使うコマンド

| コマンド | 説明 |
|---------|------|
| `make phase5` | 確認 |
| `ssh k8suser@192.168.122.10` | Control PlaneへSSH |
| `cat automation/run.log` | ログ表示 |

## 🔧 カスタマイズ

### GitHub Actions Runner追加

RunnerScaleSet は `manifests/platform/ci-cd/github-actions/runners-appset.yaml` の list generator をGitで更新します。旧Runner自動生成は使いません。

### アプリケーションデプロイ

1. app repo で image を build / push
2. infra repo の `manifests/apps/<app>/` に image tag 更新 PR を作成
3. access 変更が必要な場合は `manifests/access/<app>/` と contract 変更を別 PR にする
4. merge 後に ArgoCD が自動同期

## ⚠️ トラブルシューティング

### make all が失敗する

```bash
# ログ確認
cat automation/run.log

# フェーズを個別に再実行
make bootstrap
make phase5
```

### ノードが NotReady

```bash
# VM確認
sudo virsh list --all

# ノード詳細
kubectl describe nodes
```

### Pod が起動しない

```bash
# Pod状態確認
kubectl get pods --all-namespaces | grep -v Running

# イベント確認
kubectl get events --all-namespaces
```

## 📚 詳細ドキュメント

- [セットアップガイド](setup-guide.md) - 詳細な手順
- [運用ガイド](operations-guide.md) - 日常運用
- [アーキテクチャ](kubernetes-architecture.md) - システム設計

## 💡 Tips

1. **初回は`make all`推奨** - 依存関係を自動解決
2. **settings.toml重要** - 必須項目は必ず設定
3. **ログ確認** - `automation/run.log`に全ログ記録
4. **段階実行も可能** - `make phase1 -> make phase2 -> make bootstrap -> make phase5`

## 🎉 完了！

おめでとうございます！k8s_myHome Kubernetesクラスターが稼働しました。

次のステップ:
- アプリケーションをデプロイ
- `docs/applications.md` に従って app delivery PR を作成
- 必要なら `manifests/access/` に公開経路を追加

質問がある場合は[GitHub Issues](https://github.com/ksera524/k8s_myHome/issues)でお問い合わせください。
