# App Delivery

この文書はユーザーアプリの追加、更新、公開変更のルールです。

## 基本形

アプリは runtime と access を分けます。

| 領域 | Path |
|---|---|
| workload | `manifests/apps/<app>/` |
| access | `manifests/access/<app>/` |
| runtime Application | `manifests/bootstrap/applications/user-apps/<app>-app.yaml` |
| access Application | `manifests/bootstrap/applications/access/<app>-access.yaml` |

## 新規アプリ追加

1. `manifests/apps/<app>/` に workload-only manifest を追加します。
2. 外部公開または内部公開が必要なら `manifests/access/<app>/` を追加します。
3. `manifests/bootstrap/applications/user-apps/` に runtime 側 `Application` を追加します。
4. access owner が必要なら `manifests/bootstrap/applications/access/` に `Application` を追加します。
5. `manifests/contracts/home-lab/access-surfaces.yaml` に surface を追加します。
6. `automation/scripts/ci/validate.sh` を実行します。
7. merge 後に `kubectl get applications -n argocd` で `Synced/Healthy` を確認します。

## Image 更新

- runtime 変更は `manifests/apps/<app>/` の image tag 更新 PR にします。
- `1 app / 1 image update / 1 PR` を基本にします。
- app repo workflow / release bot は image build / push と infra repo PR 作成までを担当します。
- app delivery から `kubectl apply` / `kubectl patch` / `kubectl rollout restart` で cluster を直接変更しません。

## Access 更新

- access 変更は `manifests/access/<app>/` と `manifests/contracts/home-lab/access-surfaces.yaml` の PR にします。
- runtime PR と access PR は分けます。
- HTTPRoute には `contracts.k8s-myhome.local/access-surface` annotation を付与します。

## `latest` の扱い

`sandbox` namespace の first-party workload に限り `harbor.qroksera.com/sandbox/*:latest` を条件付きで許容します。それ以外は immutable tag を基本にします。

## 現行アプリ

| Application | Namespace | Workload path |
|---|---|---|
| `api-hub` | `sandbox` | `manifests/apps/api-hub/` |
| `blog` | `sandbox` | `manifests/apps/blog/` |
| `cooklog` | `sandbox` | `manifests/apps/cooklog/` |
| `hitomi` | `sandbox` | `manifests/apps/hitomi/` |
| `hitomi-pdf` | `sandbox` | `manifests/apps/hitomi-pdf/` |
| `hitomi-upload-viewer` | `sandbox` | `manifests/apps/hitomi-upload-viewer/` |
| `home-camera` | `sandbox` | `manifests/apps/home-camera/` |
| `selenium` | `tools` | `manifests/apps/selenium/` |

## 確認コマンド

```bash
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd
kubectl get pods -n <namespace>
kubectl get svc -n <namespace>
kubectl get httproute -n <namespace>
```
