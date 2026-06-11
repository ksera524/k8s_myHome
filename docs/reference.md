# Reference

## 重要パス

| Path | 用途 |
|---|---|
| `Makefile` | 実行入口 |
| `automation/scripts/run.sh` | phase / bootstrap runner |
| `automation/settings.toml` | local 設定 |
| `automation/run.log` | 実行ログ |
| `manifests/bootstrap/app-of-apps.yaml` | ArgoCD root `Application` |
| `manifests/bootstrap/applications/` | child `Application` |
| `manifests/apps/` | workload-only app manifest |
| `manifests/access/` | Gateway / HTTPRoute / DNS / Cloudflared |
| `manifests/contracts/home-lab/` | 非機密 contract |
| `manifests/platform/secrets/external-secrets/` | ExternalSecret 正本 |

## Make targets

```bash
make all
make phase1
make phase2
make bootstrap
make phase5
make validate
make validate-local
make recover
make upgrade-safe
make containerd-safe
```

## CI 相当検証

```bash
automation/scripts/ci/validate.sh
```

`validate.sh` は CRD catalog schema を kubeconform に追加し、schema が取得できる ArgoCD / ExternalSecret / Gateway API / cert-manager / MetalLB なども検証対象にします。

## 個別検証

```bash
shellcheck -S error -x automation/scripts/<file>.sh
yamllint -f parsable -c .yamllint.yml manifests/<dir-or-file>
kustomize build manifests/<kustomize-dir>
```

## Cluster health

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get applications -n argocd
kubectl get events -A --sort-by='.lastTimestamp'
```

## GitOps

```bash
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd
```

## Secrets

```bash
kubectl get clustersecretstores
kubectl get externalsecrets -A
```

## Access

```bash
kubectl get gateway -A
kubectl get httproute -A
kubectl get certificate -A
```

## Storage

```bash
kubectl get storageclass
kubectl get pv
kubectl get pvc -A
```

## Observability

```bash
kubectl get pods -n observability
kubectl get application observability observability-access -n argocd
```

## SSH

```bash
ssh k8suser@192.168.122.10
ssh k8suser@192.168.122.11
ssh k8suser@192.168.122.12
```
