# Operations

この文書は日常運用と保守の確認手順です。

## 基本確認

```bash
make phase5
kubectl get nodes -o wide
kubectl get applications -n argocd
kubectl get pods -A
```

`make phase5` は Node Ready、異常 Pod、ArgoCD Application、ExternalSecret、Gateway/LoadBalancer の基本状態を確認します。

## 静的検証

```bash
automation/scripts/ci/validate.sh
```

個別確認です。

```bash
shellcheck -S error -x automation/scripts/<file>.sh
yamllint -f parsable -c .yamllint.yml manifests/<dir-or-file>
kustomize build manifests/<kustomize-dir>
kustomize build manifests/<kustomize-dir> | kubeconform -strict -ignore-missing-schemas
```

## ArgoCD

```bash
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd
kubectl get application <app-name> -n argocd -o jsonpath='{.status.sync.status}'
```

## ExternalSecret

```bash
kubectl get clustersecretstore
kubectl get externalsecrets -A
kubectl describe externalsecret <name> -n <namespace>
```

## Gateway / Certificate

```bash
kubectl get gateway -A
kubectl get httproute -A
kubectl get certificate -A
kubectl describe httproute <route-name> -n <namespace>
```

## PVC / Storage

```bash
kubectl get pv
kubectl get pvc -A
kubectl get storageclass
```

## Harbor

```bash
kubectl get pods -n harbor
kubectl logs -n harbor deployment/harbor-core --since=10m
```

内部 UI は次です。

```text
https://harbor.internal.qroksera.com
```

## GitHub Actions Runner

```bash
kubectl get autoscalingrunnersets -n arc-systems
kubectl get pods -n arc-systems
kubectl get secret github-multi-repo-secret -n arc-systems
```

Runner 定義は `manifests/platform/ci-cd/github-actions/runners-appset.yaml` を Git で更新します。

## CronJob / Job

```bash
kubectl get cronjobs -A
kubectl get jobs -A
kubectl describe job <job-name> -n <namespace>
kubectl logs -n <namespace> job/<job-name>
```

Job Pod が削除済みの場合、ログは取得できません。調査が必要な CronJob は次回実行直後に Pod 名または `job-name` label でログを取得します。

```bash
kubectl get pods -n <namespace> -l job-name=<job-name>
kubectl logs -n <namespace> -l job-name=<job-name>
```

## Node メンテナンス

```bash
kubectl drain <node-name> --ignore-daemonsets
kubectl uncordon <node-name>
```

node へ入る場合です。

```bash
ssh k8suser@192.168.122.10
ssh k8suser@192.168.122.11
ssh k8suser@192.168.122.12
```

## 復旧

Ubuntu 再起動後に VM / cluster へ接続できない場合は次を使います。

```bash
make recover
```

実体は `automation/scripts/recover-after-reboot.sh` です。
