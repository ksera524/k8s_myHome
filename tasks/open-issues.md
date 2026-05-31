# 残論点アーカイブ

## 位置付け

- 本ファイルは、PH0 / PH2 で解消した論点の履歴を残す archive とする
- active な未決論点は `status.md` の `Open Decisions` だけで管理する
- `backlog.md`（PH6 後の改善項目）とは用途を分離する

## 管理ルール

- 履歴保全のため、解決済み項目は削除しない
- 新規の active 論点は本ファイルへ追加しない
- 再オープンが必要な場合は本ファイルを更新せず、`status.md` の `Open Decisions` に新規項目として起票する

## Open Issues

| ID | 論点 | 主担当 | 解決フェーズ | 完了条件 | 状態 |
|---|---|---|---|---|---|
| OI-001 | `manifests/apps/sandbox-config/` の target owner / path を確定する。`apps/` workload-only 方針と整合する shared config 置き場を決める | platform | PH0 | `sandbox-config` を `bootstrap/applications/platform/sandbox-config` -> `manifests/platform/shared-config/sandbox/` として扱う方針が `component-ownership-matrix.md` と関連 PH 文書へ反映済み | Closed |
| OI-002 | internal surface（`argocd.internal`, `harbor.internal`, `cooklog.internal`, `api-hub.internal`, `hitomi-upload-viewer.internal`）の backend 名、access contract entry、DNS publish 責務を最終確定する | network | PH0 | canonical surface ID と backend / CoreDNS / Tailscale Split DNS の publish 責務が `access-surface-matrix.md` に固定され、PH4 access contract 設計へ入力済み | Closed |
| OI-003 | `gateway LB IP`, `tailscale split DNS LB IP`, `harbor LB IP` の命名 drift を解消する。`settings.toml*` と manifest の意味対応を確定する | infra | PH0 | canonical key を `network.serviceIPs.gateway` / `network.serviceIPs.tailscaleSplitDNS` に固定し、Harbor が gateway surface 由来であることを `environment-contract-inventory.md` に反映済み | Closed |
| OI-004 | access extraction の実装順序と child Application の file split 粒度を確定する。target owner 名称は固定済みとして、`apps/argocd`, `apps/rustfs`, `apps/cloudflared`, app 配下 route、CoreDNS host overrides、Tailscale split DNS、Harbor routes をどの順で `manifests/access/**` へ移すか決める | gitops | PH2 | access owner を `service access` と `shared access plane` の 2 層に固定し、`gateway-shared`, `cloudflared`, `dns-core`, `dns-tailscale` を shared owner、service ごとの route/policy を service owner に分けた上で、抽出順と sync wave が PH2 文書に反映済み | Closed |
| OI-005 | `harbor` / `harbor-patch` の split owner をどう扱うか確定する。route、cleanup CronJob、node-mutations をどこまで platform / access / optional ops に分けるか決める | platform | PH2 | `platform/harbor` が Helm release と cleanup CronJob、`access/harbor-access` が route / policy / publication、`node-mutations` が opt-in overlay という境界が `component-ownership-matrix.md` と PH2 対象範囲へ反映済み | Closed |
| OI-006 | empty dir / dead path（`manifests/apps/harbor`, `monitoring`, `postgresql`, `slack`, `user-up`）の扱いを確定する。削除か reservation かを決める | gitops | PH2 | empty dir / dead path は reservation せず削除する方針が `decision-log.md` / `legacy-removal-inventory.md` / PH2 文書へ反映済み | Closed |

## メモ

- `B-001`（代替監視基盤）は PH6 後の改善項目なので `backlog.md` に残す
- current-state / target-state の運用判断は `status.md` と各 PH 文書を正とする
