# アプリケーション管理

## 概要

現在の GitOps 構成では、アプリを次の 3 層で管理します。

- `manifests/apps/`: workload-only マニフェスト
- `manifests/access/`: 公開/接続系リソース
- `manifests/bootstrap/applications/**`: ArgoCD child `Application`

root `Application` は `manifests/bootstrap/app-of-apps.yaml` の `bootstrap-root` です。

## child Application 一覧

### Platform

| Application | Namespace | 参照先 |
|---|---|---|
| `argocd-core` | `argocd` | `manifests/platform/argocd-config/` |
| `external-secrets-operator` | `external-secrets-system` | chart |
| `config-secrets` | `monitoring` | `manifests/platform/secrets/external-secrets/` |
| `platform` | `argocd` | `manifests/platform/ci-cd/github-actions/` |
| `harbor` | `harbor` | `manifests/platform/harbor/` |
| `rustfs` | `rustfs` | `manifests/platform/rustfs/` |
| `sandbox-config` | `sandbox` | `manifests/platform/shared-config/sandbox/` |
| `monitoring` | `monitoring` | Grafana chart + `manifests/monitoring/` values |

### User Apps

| Application | Namespace | workload path |
|---|---|---|
| `api-hub` | `sandbox` | `manifests/apps/api-hub/` |
| `blog` | `sandbox` | `manifests/apps/blog/` |
| `cooklog` | `sandbox` | `manifests/apps/cooklog/` |
| `hitomi` | `sandbox` | `manifests/apps/hitomi/` |
| `hitomi-pdf` | `sandbox` | `manifests/apps/hitomi-pdf/` |
| `hitomi-upload-viewer` | `sandbox` | `manifests/apps/hitomi-upload-viewer/` |
| `home-camera` | `sandbox` | `manifests/apps/home-camera/` |
| `selenium` | `tools` | `manifests/apps/selenium/` |

### Access

| Application | Namespace | access path |
|---|---|---|
| `gateway-shared` | `nginx-gateway` | `manifests/access/gateway/` |
| `argocd-access` | `argocd` | `manifests/access/argocd/` |
| `harbor-access` | `harbor` | `manifests/access/harbor/` |
| `rustfs-access` | `rustfs` | `manifests/access/rustfs/` |
| `blog-access` | `sandbox` | `manifests/access/blog/` |
| `cooklog-access` | `sandbox` | `manifests/access/cooklog/` |
| `api-hub-access` | `sandbox` | `manifests/access/api-hub/` |
| `hitomi-upload-viewer-access` | `sandbox` | `manifests/access/hitomi-upload-viewer/` |
| `cloudflared` | `cloudflared` | `manifests/access/cloudflared/` |
| `dns-core` | `kube-system` | `manifests/access/dns/core/` |
| `dns-tailscale` | `tailscale` | `manifests/access/dns/tailscale/` |

## アプリごとの要点

### API Hub

| 項目 | 内容 |
|---|---|
| Namespace | `sandbox` |
| Image | `harbor.qroksera.com/sandbox/api-hub:<tag>` |
| Service | `NodePort` (`32001`) |
| Access | `manifests/access/api-hub/` |

### Blog

| 項目 | 内容 |
|---|---|
| Namespace | `sandbox` |
| Image | `harbor.qroksera.com/sandbox/blog:<tag>` |
| Access | `blog.qroksera.com` は `manifests/access/blog/` |

### Cooklog

| 項目 | 内容 |
|---|---|
| Namespace | `sandbox` |
| Image | `harbor.qroksera.com/sandbox/cooklog:<tag>` |
| Access | `cooklog.internal.qroksera.com` は `manifests/access/cooklog/` |

### Hitomi Upload Viewer

| 項目 | 内容 |
|---|---|
| Namespace | `sandbox` |
| Image | `harbor.qroksera.com/sandbox/hitomi-upload-viewer:<tag>` |
| Access | `hitomi-upload-viewer.internal.qroksera.com` は `manifests/access/hitomi-upload-viewer/` |

### Home Camera

| 項目 | 内容 |
|---|---|
| Namespace | `sandbox` |
| 種別 | CronJob |
| 設定 | `RTSP_URL` は app 固有の非機密設定として `manifests/apps/home-camera/manifest.yaml` に置く |

### RustFS / Harbor / Cloudflared

| 項目 | 内容 |
|---|---|
| `rustfs` runtime | `manifests/platform/rustfs/` |
| `rustfs` access | `manifests/access/rustfs/` |
| `harbor` runtime | `manifests/platform/harbor/` |
| `harbor` access | `manifests/access/harbor/` |
| `cloudflared` | `manifests/access/cloudflared/` |

## sandbox 共有接続情報

`sandbox` 向けの非機密共有設定は `platform/shared-config` にまとめています。

| 項目 | 内容 |
|---|---|
| Namespace | `sandbox` |
| ConfigMap | `sandbox-connection-info` |
| 参照 | `manifests/platform/shared-config/sandbox/manifest.yaml` |

現在のキー:

- `RUSTFS_S3_ENDPOINT`
- `RUSTFS_S3_REGION`

## 新規アプリ追加

1. `manifests/apps/<app-name>/` に workload-only manifest を追加
2. 外部公開や内部公開が必要なら `manifests/access/<app-name>/` を追加
3. `manifests/bootstrap/applications/user-apps/` に runtime 側 `Application` を追加
4. access owner が必要なら `manifests/bootstrap/applications/access/` に `Application` を追加
5. `kubectl get applications -n argocd` で `Synced/Healthy` を確認

## 運用確認コマンド

```bash
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd
kubectl get pods -n <namespace>
kubectl get svc -n <namespace>
kubectl get httproute -n <namespace>
```
