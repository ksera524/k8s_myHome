
# ArgoCD Infrastructure Management

Phase4で自動インストールされるArgoCDを使用してインフラコンポーネントを管理します。

## 概要

ArgoCDによるGitOpsアプローチで以下のコンポーネントを管理：

- **MetalLB**: LoadBalancer機能
- **NGINX Ingress Controller**: HTTP/HTTPSルーティング
- **cert-manager**: TLS証明書自動管理
- **Harbor**: プライベートコンテナレジストリ
- **Actions Runner Controller**: GitHub Actions自動実行環境

## ファイル構成

- `app-of-apps.yaml`: メインアプリケーション（App of Apps パターン）
- `metallb-complete.yaml`: MetalLBアプリケーション定義と設定
- `ingress-nginx-app.yaml`: NGINX Ingress Controllerアプリケーション定義
- `cert-manager-complete.yaml`: cert-managerアプリケーション定義と設定
- `harbor-complete.yaml`: Harborアプリケーション定義と証明書設定
- `storage-complete.yaml`: ストレージクラス設定
- `actions-runner-controller-app.yaml`: ARCアプリケーション定義
- `github-runner-config.yaml`: GitHub Runner設定

## セットアップ手順

### 1. ArgoCD App of Apps デプロイ

```bash
# GitリポジトリURLを実際のものに変更
kubectl apply -f app-of-apps.yaml
```

### 2. ArgoCD UI アクセス

```bash
# 初期パスワード取得
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port forwarding
kubectl port-forward svc/argocd-server -n argocd --address 0.0.0.0 8080:443
```

### 3. Ingress経由でのアクセス（オプション）

```bash
# ArgoCD Ingress作成
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
spec:
  ingressClassName: nginx
  rules:
  - host: argocd.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
EOF
```

## 使用方法

### ArgoCD CLI

```bash
# ArgoCD CLI インストール
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd /usr/local/bin/argocd

# ログイン
argocd login argocd.local --username admin --password <password>

# アプリケーション一覧
argocd app list

# 同期実行
argocd app sync infrastructure
```

### 手動同期

```bash
# Kubernetesマニフェストで直接同期
kubectl patch application infrastructure -n argocd --type merge --patch '{"operation":{"sync":{"revision":"HEAD"}}}'
```

## トラブルシューティング

### アプリケーションが同期されない場合

```bash
# アプリケーション状態確認
kubectl get applications -n argocd

# 詳細確認
kubectl describe application infrastructure -n argocd

# ArgoCD Serverログ確認
kubectl logs -n argocd -l app.kubernetes.io/component=server
```

### リポジトリアクセス問題

```bash
# リポジトリ接続確認
argocd repo list

# リポジトリ追加（プライベートリポジトリの場合）
argocd repo add https://github.com/YOUR_USERNAME/k8s_myHome.git --username <username> --password <token>
```

## 注意事項

1. `app-of-apps.yaml`内のリポジトリURLを実際のものに変更してください
2. プライベートリポジトリの場合は認証情報の設定が必要です
3. 各コンポーネントのHelmチャートバージョンは定期的に更新してください
4. Harbor使用前に管理者パスワードを変更してください（デフォルト: Harbor12345）
5. GitHub Actions Runner Controller使用前に`github-runner-config.yaml`でGitHubトークンを設定してください
6. リポジトリ名/組織名を実際のものに変更してください
