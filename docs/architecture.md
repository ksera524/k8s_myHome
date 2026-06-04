# Architecture

この文書は current main のクラスタ全体像をまとめます。

## 構成

ホームラボ向けの 3 node Kubernetes クラスタです。

| Node | Role | 既定 IP |
|---|---|---|
| `k8s-control-plane` | control plane | `192.168.122.10` |
| `k8s-worker1` | worker | `192.168.122.11` |
| `k8s-worker2` | worker | `192.168.122.12` |

主な基盤コンポーネントは次です。

| 領域 | コンポーネント |
|---|---|
| GitOps | ArgoCD App-of-Apps |
| Network | Flannel, MetalLB, NGINX Gateway Fabric, Gateway API |
| TLS | cert-manager, Cloudflare DNS-01 |
| Secrets | External Secrets Operator, Pulumi ESC |
| Registry | Harbor |
| Storage | local-path, local storage classes, RustFS |
| CI/CD | Actions Runner Controller |
| Observability | VictoriaMetrics, kube-state-metrics |

## Owner 分離

`manifests/` は責務ごとに分割します。

| Path | 責務 |
|---|---|
| `bootstrap/` | root/child ArgoCD `Application` |
| `core/` | Namespace / StorageClass / cluster-wide 基本設定 |
| `infrastructure/` | networking / security / storage などクラスタ基盤 |
| `platform/` | ArgoCD 設定、CI/CD、Secrets、Harbor、RustFS、observability |
| `access/` | Gateway / HTTPRoute / DNS / Cloudflared |
| `contracts/` | 非機密 environment / access contract |
| `apps/` | ユーザーアプリ workload |

## Runtime / Access 分離

- `apps/` には Deployment / Service / CronJob など workload 本体だけを置きます。
- `access/` には HTTPRoute / Gateway / Cloudflared / DNS publish など接続系を置きます。
- 複数 workload が共有する非機密設定は `platform/shared-config/` に置きます。

## App-of-Apps

root `Application` は `manifests/bootstrap/app-of-apps.yaml` です。

適用順序と依存関係は [App-of-Apps / Sync Wave 図](diagrams/app-of-apps-sync-wave.md) を参照してください。
