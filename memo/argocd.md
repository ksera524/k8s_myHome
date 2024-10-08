
## Helm
[helm](https://artifacthub.io/packages/helm/argo/argo-cd)

## 各種コマンド
```bash
#初期パスワード取得
argocd admin initial-password -n argocd
#Port開放
kubectl port-forward svc/argocd-server -n argocd --address 0.0.0.0 8080:443
```
