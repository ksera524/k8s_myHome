# GitOps

このリポジトリは ArgoCD App-of-Apps で Kubernetes リソースを同期します。

## 正本

- GitOps 管理対象: `manifests/`
- bootstrap root: `manifests/bootstrap/app-of-apps.yaml`
- child `Application`: `manifests/bootstrap/applications/**`
- ArgoCD 本体・CRD・設定: `manifests/platform/argocd-config/`

## アプリの安定版追従

Renovate が毎日、公開イメージ・外部 Helm Chart の更新 PR を作成し、PR の HEAD を検証します。
ArgoCD 本体・同梱 chart・ARC の連動更新は手動 updater を使い、マージ後は ArgoCD が同期します。
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

## デプロイ結果の Slack 通知

`apps` AppProject の全 Application は Argo CD Notifications で次のイベントを通知する。

- 同期操作が `Succeeded`、かつ `Synced` / `Healthy` になった時点の完了通知。
  実際に同期した `operationState.syncResult.revision` ごとに重複を抑える。
- 同期操作が `Error` / `Failed` になった時点の失敗通知。
  `operationState.startedAt` ごとに重複を抑え、同じ SHA の再実行失敗も通知する。

通知にはアプリ名、結果、Git revision、Argo CD のアプリ画面への URL を含める。
revision が解決できなかった失敗は「未解決」と表示する。
これはデプロイ用リポジトリの SHA であり、アプリのソースコードの SHA とは限らない。
継続的な health / OutOfSync 異常は既存の監視で扱う。
初回有効化時は、既に条件を満たしているアプリの結果も通知されることがある。

設定は `manifests/platform/argocd-config/argocd-notifications.yaml`、購読は
`argocd-projects.yaml` の `apps` に集約する。追加のユーザーアプリも同じ Project に属すれば通知対象になる。
現在のユーザーアプリの単一 Git source を前提とするため、multi-source 化時は revision の扱いを見直す。

通知先は Alertmanager と同じ Slack Incoming Webhook。
Pulumi ESC の既存キー `alertmanager-slack-webhook-url` を ExternalSecret で
`argocd/argocd-notifications-secret` の `slack-webhook-url` に同期する。
空の Secret は Argo CD upstream が作成し、ESO が `creationPolicy: Merge` で値を注入する。
Webhook URL を Git に記録しない。通知先を分ける場合は ExternalSecret の remoteRef を専用キーへ変更する。

GitOps 同期後は次で Secret の準備状況と controller のログを確認できる。

```bash
kubectl -n argocd get externalsecret argocd-notifications-secret
kubectl -n argocd logs deployment/argocd-notifications-controller --since=10m
```

ESO が値を注入するまでは通知できない。実際の受信確認は次回のアプリ変更の同期で行う。
設定形式は [Webhook](https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/services/webhook/)
と [Triggers](https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/triggers/) を参照。

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
