# GitOps

このリポジトリは ArgoCD App-of-Apps で Kubernetes リソースを同期します。

## 正本

- GitOps 管理対象: `manifests/`
- bootstrap root: `manifests/bootstrap/app-of-apps.yaml`
- child `Application`: `manifests/bootstrap/applications/**`
- ArgoCD 本体・CRD・設定: `manifests/platform/argocd-config/`

## アプリの安定版追従

毎日、固定版の更新候補を検出して検証済みPRを作成します。マージ後はArgoCD本体も自動同期されます。
対象範囲、可変タグの扱い、手動マージの運用は[アプリの定期更新](application-auto-updates.md)を参照してください。

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

### NGINX Gateway Fabric の更新

- 現行の組み合わせは NGF `2.8.0` / Gateway API `1.6.3`。
- Gateway API の CRD は `manifests/infrastructure/networking/nginx-gateway-fabric/gateway-api/`、
  NGF 本体と専用 CRD は `manifests/bootstrap/applications/infrastructure/nginx-gateway-fabric.yaml`
  の Helm chart を正本として ArgoCD で更新する。
- 更新時は Gateway API の変更を先に push し、`gateway-api` の同期完了後に NGF の chart を更新する。
  別 Application の子リソースまで sync wave だけで適用完了を保証すると考えない。
- 2026-10-17 の 413 再発は NGF 2.3.0 の [#4890](https://github.com/nginx/nginx-gateway-fabric/issues/4890)
  によるもの。RustFS の同一パスに対する method/header 分岐が、無関係な api-hub / Harbor の
  `ClientSettingsPolicy` を `TargetConflict` にし、サイズ制限解除が実設定から外れた。
- 更新後は Application の `Synced` / `Healthy` に加え、各 `ClientSettingsPolicy` の
  `Accepted=True` / `Programmed=True`、NGINX 実設定の `client_max_body_size 0` を確認する。
  api-hub にはサイズの大きい不正 JSON を送り、413 ではなく JSON 解析エラーになることを確認する。
  不正 JSON を使うことで S3 にオブジェクトを書き込まずに受信経路を検証できる。

### 共通ルール

- 変更は Git に反映し、ArgoCD で同期します。
- 手動 `kubectl apply` は bootstrap 最小限または緊急時の暫定対応に限ります。
- 緊急時に手動変更した場合も、最終状態は Git へ戻します。
- Runner 定義は `manifests/platform/ci-cd/github-actions/runners-appset.yaml` を Git で更新します。
