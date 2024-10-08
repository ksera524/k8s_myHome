## helm
[helm](https://artifacthub.io/packages/helm/argo/argo-workflows)

## 各種コマンド
```bash
#workflowの起動
curl -sk localhost:30001/api/v1/events/${namespace}/${discriminator} -H "Authorization: $TOKEN" -d  '{"message": "s3s"}'

sudo kubectl delete clusterrole argowork
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

sudo kubectl delete sa argowork -n argoworkflow
sudo kubectl create sa argowork -n argoworkflow

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

ARGO_TOKEN="Bearer $(kubectl get secret argowork.service-account-token -n argoworkflow -o=jsonpath='{.data.token}' | base64 --decode)"

sudo kubectl get pods -n argoworkflow
sudo kubectl exec -it argo-workflow-argo-workflows-server-589ddfc7d-xrn4c -n argoworkflow -- argo auth token

sudo kubectl get deployment -n argoworkflow

kubectl rollout restart deployment -n argoworkflow argo-workflow-argo-workflows-server

sudo kubectl exec -it argo-workflow-argo-workflows-server-58f545c74-b46kg -n argoworkflow -- argo auth token
```

## 参考資料

1. [使いこなせ！Argo Workflows / How to use Argo Workflows](https://speakerdeck.com/makocchi/how-to-use-argo-workflows)
2. [argo-workflows/examples](https://github.com/argoproj/argo-workflows/tree/main/examples)