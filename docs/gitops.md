# GitOps

このリポジトリは ArgoCD App-of-Apps で Kubernetes リソースを同期します。

## 正本

- GitOps 管理対象: `manifests/`
- bootstrap root: `manifests/bootstrap/app-of-apps.yaml`
- child `Application`: `manifests/bootstrap/applications/**`
- ArgoCD 設定: `manifests/platform/argocd-config/`

## Application 配置

child `Application` は次に置きます。

| Path | Project | 対象 |
|---|---|---|
| `bootstrap/applications/core/` | `core` | cluster 基礎 |
| `bootstrap/applications/infrastructure/` | `infrastructure` | クラスタ基盤 |
| `bootstrap/applications/platform/` | `platform` | 運用基盤 |
| `bootstrap/applications/access/` | `access` | 公開/接続系 |
| `bootstrap/applications/user-apps/` | `apps` | workload |

`core/` 以下には `Application` 定義を置きません。

## Sync Wave

適用順序は annotation `argocd.argoproj.io/sync-wave` で制御します。図は次です。

```text
docs/diagrams/app-of-apps-sync-wave.md
```

`app-of-apps.yaml` や sync wave を変更した場合は図も更新します。

## targetRevision

`manifests/bootstrap/**` の `targetRevision` は `HEAD` を維持します。`main` へ変更しません。

## 確認コマンド

```bash
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd
kubectl get application <app-name> -n argocd -o jsonpath='{.status.sync.status}'
```

## 運用ルール

- 変更は Git に反映し、ArgoCD で同期します。
- 手動 `kubectl apply` は bootstrap 最小限または緊急時の暫定対応に限ります。
- 緊急時に手動変更した場合も、最終状態は Git へ戻します。
- Runner 定義は `manifests/platform/ci-cd/github-actions/runners-appset.yaml` を Git で更新します。
