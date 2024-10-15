## helm
[helm](https://artifacthub.io/packages/helm/argo/argo-workflows)

## 各種コマンド
```bash
#workflowをhttp経由で起動する
curl -sk localhost:30001/api/v1/events/${namespace}/${discriminator} -H "Authorization: $TOKEN" -d  '{"message": "s3s"}'
```
```bash
#ClusterRoleの削除
sudo kubectl delete clusterrole argowork

#ClusterRoleの作成
sudo kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argowork
rules:
- apiGroups: ["argoproj.io"]
  resources: ["workflows", "workflows/finalizers", "workflowtemplates", "workflowtemplates/finalizers", "cronworkflows", "cronworkflows/finalizers", "workfloweventbindings", "workfloweventbindings/finalizers", "clusterworkflowtemplates", "clusterworkflowtemplates/finalizers"]
  verbs: ["create", "delete", "deletecollection", "get", "list", "patch", "update", "watch"]
- apiGroups: [""]
  resources: ["pods", "pods/exec", "pods/log", "services", "configmaps"]
  verbs: ["create", "delete", "deletecollection", "get", "list", "patch", "update", "watch"]
EOF
```

```bash
#service acountの削除
sudo kubectl delete sa argowork -n argoworkflow
#service acountの作成
sudo kubectl create sa argowork -n argoworkflow
```
```bash
#ClusterRoleBindingの作成
sudo kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argowork
subjects:
- kind: ServiceAccount
  name: argowork
  namespace: argoworkflow
roleRef:
  kind: ClusterRole
  name: argowork
  apiGroup: rbac.authorization.k8s.io
EOF
```
```bash
#Access Tokenの取得1
ARGO_TOKEN="Bearer $(kubectl get secret argowork.service-account-token -n argoworkflow -o=jsonpath='{.data.token}' | base64 --decode)"
#Access Tokenの取得2
sudo kubectl get deployment -n argoworkflow
sudo kubectl exec -it argo-workflow-argo-workflows-server-${podId} -n argoworkflow -- argo auth token
```

## 参考資料

1. [使いこなせ！Argo Workflows / How to use Argo Workflows](https://speakerdeck.com/makocchi/how-to-use-argo-workflows)
2. [argo-workflows/examples](https://github.com/argoproj/argo-workflows/tree/main/examples)