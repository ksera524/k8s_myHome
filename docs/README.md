# k8s_myHome Docs

このディレクトリは current main / live repo の実用手順を正とします。将来計画、構造改革の履歴、未実装の target-state は `tasks/` を参照してください。

## 読む順番

1. 初回構築は [bootstrap](bootstrap.md)
2. 全体像は [architecture](architecture.md)
3. GitOps 運用は [gitops](gitops.md)
4. マニフェスト配置は [manifests](manifests.md)
5. 日常運用は [operations](operations.md)
6. 障害時は [troubleshooting](troubleshooting.md)

## ドキュメント一覧

| 文書 | 用途 |
|---|---|
| [bootstrap](bootstrap.md) | 初期設定、`make all`、`make bootstrap`、`make phase5` |
| [architecture](architecture.md) | クラスタ構成、主要コンポーネント、owner 分離 |
| [gitops](gitops.md) | ArgoCD App-of-Apps、Application、Sync Wave |
| [manifests](manifests.md) | `manifests/` 配置規約、runtime/access 分離 |
| [app-delivery](app-delivery.md) | 新規アプリ追加、image tag 更新、access 追加 |
| [access](access.md) | Gateway、HTTPRoute、DNS、Cloudflared、access surface |
| [secrets](secrets.md) | External Secrets Operator、Pulumi ESC、Secret 配置 |
| [observability](observability.md) | VictoriaMetrics、kube-state-metrics、CRD metrics |
| [operations](operations.md) | 日常確認、保守、CronJob/Job 調査 |
| [troubleshooting](troubleshooting.md) | 一次切り分け、復旧観点、ログ収集 |
| [upgrade](upgrade.md) | Kubernetes / containerd upgrade、rollback |
| [reference](reference.md) | 重要パス、検証コマンド、kubectl コマンド集 |
| [App-of-Apps / Sync Wave 図](diagrams/app-of-apps-sync-wave.md) | ArgoCD 適用順序の図 |

## 運用原則

- GitOps が正です。Kubernetes リソースの最終状態は `manifests/` に置きます。
- `automation/` はローカル bootstrap / 運用スクリプト用です。
- `docs/` は current-state のみを書きます。計画や履歴は `tasks/` に分離します。
- `Makefile` と `automation/scripts/run.sh` が実行フローの正です。
