# Observability

この文書は current main の observability 構成です。

## コンポーネント

| Component | Path | 用途 |
|---|---|---|
| VictoriaMetrics | `manifests/platform/observability/victoria-metrics.yaml` | metrics storage / UI |
| kube-state-metrics | `manifests/platform/observability/kube-state-metrics.yaml` | Kubernetes / CRD state metrics |
| observability access | `manifests/access/observability/` | internal HTTPRoute |

## Access

内部 UI は次で公開します。

```text
https://observability.internal.qroksera.com/vmui/
```

backend は `observability` namespace の `victoria-metrics:8428` です。

## CRD Metrics

kube-state-metrics の custom-resource-state metrics で次を取り込みます。

| Metric family | 対象 |
|---|---|
| `kube_argocd_application_*` | ArgoCD Application |
| `kube_externalsecret_status_condition` | ExternalSecret |
| `kube_gateway_status_condition` | Gateway |
| `kube_httproute_parent_status_condition` | HTTPRoute |
| `kube_certificate_status_condition` | cert-manager Certificate |

## Metrics API との違い

VictoriaMetrics は metrics storage です。`kubectl top nodes` / `kubectl top pods -A` が使う Kubernetes Metrics API とは別です。

`kubectl top` を使うには metrics-server が必要です。

## 確認コマンド

```bash
kubectl get pods -n observability
kubectl get httproute -n observability
kubectl get application observability observability-access -n argocd
```

Gateway 経由の確認例です。

```bash
curl -k -I https://observability.internal.qroksera.com/vmui/
```
