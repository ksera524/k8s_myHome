# 残論点一覧

## 目的

- 現時点で未確定の構造改革論点を課題として追跡する
- `backlog.md`（PH6 後の改善項目）とは分離し、改革中に解くべき論点だけを扱う

## 管理ルール

- 1 行 = 1 論点
- `主担当` と `解決フェーズ` を必須にする
- `完了条件` は、方針が確定したと判断できる状態で書く
- 解決した項目は削除せず、`状態` を `Closed` に変更する

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
- 本ファイルは「改革を進めるために今決める必要がある論点」のみを扱う
