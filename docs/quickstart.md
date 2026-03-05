# クイックスタートガイド

## 🚀 5分でk8s_myHomeを起動

このガイドでは、k8s_myHome Kubernetesクラスターを最速でセットアップする方法を説明します。

## 前提条件

- Ubuntu 24.04 LTS
- 16GB+ RAM
- 200GB+ ストレージ
- インターネット接続

## 事前ツール確認

CI と同等の検証をローカルで実行するため、以下のツールが必要です。

```bash
command -v shellcheck
command -v yamllint
command -v kustomize
```

導入済みかの確認と検証は次で実行できます。

```bash
automation/scripts/ci/validate.sh
```

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
| `make add-runner REPO=name MIN=1 MAX=3 STRATEGY=latest` | GitHub Runner追加 |

## 🔧 カスタマイズ

### GitHub Actions Runner追加

```bash
# settings.tomlに追加
arc_repositories = [
    ["your-repo", 1, 3, "Your repository", "latest"],
]

# Runner作成
make add-runners-all
```

### アプリケーションデプロイ

1. `manifests/apps/`にアプリケーションマニフェスト作成
2. Git commit & push
3. ArgoCDが自動デプロイ

## ⚠️ トラブルシューティング

### make all が失敗する

```bash
# ログ確認
cat automation/run.log

# フェーズを個別に再実行
make phase3
make phase4
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
4. **段階実行も可能** - `make phase1`〜`make phase5`

## 🎉 完了！

おめでとうございます！k8s_myHome Kubernetesクラスターが稼働しました。

次のステップ:
- アプリケーションをデプロイ
- 監視ダッシュボードを確認
- CI/CDパイプラインを構築

質問がある場合は[GitHub Issues](https://github.com/ksera524/k8s_myHome/issues)でお問い合わせください。
