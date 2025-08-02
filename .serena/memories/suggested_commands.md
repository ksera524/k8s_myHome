# 推奨コマンド集

## 完全デプロイワークフロー
```bash
# Host Setup: ホスト準備
./automation/host-setup/setup-host.sh
# (logout/login required for group membership)
./automation/host-setup/setup-storage.sh  
./automation/host-setup/verify-setup.sh

# Infrastructure: VM作成 + Kubernetesクラスタ
cd automation/infrastructure && ./clean-and-deploy.sh

# Platform: コアプラットフォームサービス + Harbor証明書修正 + GitHub Actions
cd ../platform && ./phase4-deploy.sh

# または個別にGitHub Actions設定
./setup-arc.sh
```

## 運用・トラブルシューティング
```bash
# VM管理
sudo virsh list --all
sudo virsh console k8s-control-plane-X

# クラスタアクセス
ssh k8suser@192.168.122.10
kubectl get nodes

# ArgoCD アクセス（port-forward）
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Harbor アクセス
kubectl port-forward svc/harbor-core -n harbor 8081:80
# Default: admin/Harbor12345

# インフラ状態確認
kubectl get pods --all-namespaces
kubectl -n ingress-nginx get service ingress-nginx-controller  # LoadBalancer IP
kubectl get applications -n argocd  # ArgoCD同期状態
```

## テスト・検証
```bash
# コンポーネント検証
./automation/host-setup/verify-setup.sh  # Host Setup
terraform plan -out=tfplan  # Infrastructure検証 (in infrastructure/)
ssh k8suser@192.168.122.10 'kubectl get nodes'  # Infrastructure結果確認
kubectl get pods --all-namespaces | grep -E "(metallb|ingress|cert-manager|argocd)"  # Platform
```

## 開発ユーティリティ
```bash
# Git操作
git status
git add .
git commit -m "日本語コミットメッセージ"
git push

# ファイル検索
find . -name "*.yaml" -type f
grep -r "kubectl create secret" automation/
```