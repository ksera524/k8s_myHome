# アプリケーション管理

## 概要

このドキュメントは、`manifests/apps/` と `manifests/bootstrap/applications/user-apps/` の定義を基準に、現在運用中のアプリ構成をまとめたものです。

## 現在のアプリ一覧（GitOps管理対象）

| アプリ | Namespace | 主な種類 | 参照先 |
|------|------|------|------|
| argocd-external | argocd | HTTPRoute | `manifests/apps/argocd/` |
| blog | sandbox | Deployment / Service / HTTPRoute | `manifests/apps/blog/` |
| cloudflared | cloudflared | Deployment / ConfigMap | `manifests/apps/cloudflared/` |
| cooklog | sandbox | Deployment / Service / HTTPRoute | `manifests/apps/cooklog/` |
| hitomi | sandbox | CronJob | `manifests/apps/hitomi/` |
| rustfs-external | rustfs | HTTPRoute | `manifests/apps/rustfs/` |
| selenium | tools | Deployment / Service | `manifests/apps/selenium/` |
| slack | sandbox | Deployment / Service(NodePort) | `manifests/apps/slack/` |

補足:

- `rustfs` 本体は `manifests/apps/rustfs/` ではなく Helm Application（`rustfs-app.yaml`）でデプロイ
- 監視スタック（Grafana k8s-monitoring）は `manifests/apps/` ではなく Platform レイヤーで管理

## アプリごとの要点

### Slack

| 項目 | 内容 |
|------|------|
| Namespace | `sandbox` |
| Image | `harbor.qroksera.com/sandbox/slack.rs:<tag>` |
| Service | `NodePort` (`32001`) |
| Secret | `slack` (`SLACK_BOT_TOKEN`) |
| 参照 | `manifests/apps/slack/manifest.yaml` |

### Cloudflared

| 項目 | 内容 |
|------|------|
| Namespace | `cloudflared` |
| Image | `cloudflare/cloudflared:latest` |
| 種別 | Deployment（2 replicas） |
| Secret | `cloudflared`（credentials.json用途） |
| 参照 | `manifests/apps/cloudflared/manifest.yaml`, `manifests/apps/cloudflared/cloudflared-config.yaml` |

### Blog

| 項目 | 内容 |
|------|------|
| Namespace | `sandbox` |
| Image | `harbor.qroksera.com/sandbox/blog:<tag>` |
| 公開 | `blog.qroksera.com`（Gateway API） |
| 参照 | `manifests/apps/blog/manifest.yaml` |

### Cooklog

| 項目 | 内容 |
|------|------|
| Namespace | `sandbox` |
| Image | `harbor.qroksera.com/sandbox/cooklog:<tag>` |
| 公開 | `cooklog.internal.qroksera.com`（内部公開） |
| 参照 | `manifests/apps/cooklog/manifest.yaml` |

### Hitomi

| 項目 | 内容 |
|------|------|
| Namespace | `sandbox` |
| 種別 | CronJob |
| Image | `harbor.qroksera.com/sandbox/hitomi:<tag>` |
| 参照 | `manifests/apps/hitomi/manifest.yaml` |

### Selenium

| 項目 | 内容 |
|------|------|
| Namespace | `tools` |
| 種別 | Deployment / Service(ClusterIP) |
| Image | `selenium/standalone-chrome:latest` |
| 参照 | `manifests/apps/selenium/manifest.yaml` |

### ArgoCD / RustFS 外部公開

| ルート | Namespace | 公開ホスト | 参照 |
|------|------|------|------|
| ArgoCD | `argocd` | `argocd.qroksera.com` / `argocd.internal.qroksera.com` | `manifests/apps/argocd/manifest.yaml` |
| RustFS Console | `rustfs` | `rustfs.qroksera.com` | `manifests/apps/rustfs/manifest.yaml` |

## sandbox 共有接続情報

`sandbox` 向けの非機密接続情報は `ConfigMap` にまとめています。

| 項目 | 内容 |
|------|------|
| Namespace | `sandbox` |
| ConfigMap | `sandbox-connection-info` |
| 参照 | `manifests/apps/sandbox-config/manifest.yaml` |

現在のキー:

- `RUSTFS_S3_ENDPOINT`
- `RUSTFS_S3_REGION`

`rustfs-auth` Secret（`RUSTFS_ACCESS_KEY` / `RUSTFS_SECRET_KEY`）は ExternalSecret で同期されます。

## 新規アプリ追加（実運用フロー）

1. `manifests/apps/<app-name>/` を作成し、`kustomization.yaml` とマニフェストを配置
2. 必要なら `manifests/platform/secrets/external-secrets/external-secret-resources.yaml` に ExternalSecret を追加
3. `manifests/bootstrap/applications/user-apps/<app-name>-app.yaml` に ArgoCD Application を追加
4. `kubectl get applications -n argocd` で `Synced/Healthy` を確認

Application 定義例:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app-name>
  namespace: argocd
spec:
  project: apps
  source:
    repoURL: https://github.com/ksera524/k8s_myHome.git
    targetRevision: HEAD
    path: manifests/apps/<app-name>
  destination:
    server: https://kubernetes.default.svc
    namespace: <namespace>
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

## 運用確認コマンド

```bash
# Application 一覧
kubectl get applications -n argocd

# アプリの詳細
kubectl describe application <app-name> -n argocd

# Pod/Service/Route
kubectl get pods -n <namespace>
kubectl get svc -n <namespace>
kubectl get httproute -n <namespace>
```
