# 構造改革ステータス

最終更新日: 2026-05-31

## Current Phase

- PH2: GitOps Topology Normalization and Access Extraction（access owner 粒度と抽出順を確定）

## This Week

- [x] `tasks/` 管理基盤の初期作成
- [x] PH0 方針の確定（旧仕様完全削除 / main 併存なし）
- [x] `apps/` workload-only / `access/` top-level ドメイン方針を確定
- [x] フェーズ順序を `PH0 -> PH2 -> PH4 -> PH1 -> PH3 -> PH5 -> PH6` へ更新
- [x] PH0 / PH2 / PH4 を access 分離前提へ更新
- [x] PH1 / PH3 / PH5 / PH6 を新 topology 前提へ更新
- [x] `sandbox latest` 条件付き許容方針を PH3/PH5/PH6 に反映
- [x] Harbor/RustFS の clean rebuild 前提を cutover 条件へ反映
- [x] `validate.sh` を唯一の公開判定入口とする方針を文書に固定
- [x] planning artifact（ownership / surface / contract inventory）の雛形を追加
- [x] planning artifact の初期入力を具体化
- [x] 残論点を `tasks/open-issues.md` に課題として集約
- [x] `sandbox-config` を platform shared config owner へ再分類する方針を確定
- [x] internal access surface の canonical ID と DNS publish 責務を確定
- [x] access URL を surface から導出し、`gateway` / `tailscaleSplitDNS` の canonical service IP 命名を確定
- [x] Harbor の runtime / access / optional ops 境界を確定
- [x] access owner を `service access` と `shared access plane` の 2 層に固定
- [x] `Gateway` resource / listener 基盤を `gateway-shared` owner に寄せる方針を確定
- [x] empty dir / dead path は reservation せず削除する方針を確定
- [x] `ExternalSecret` 分割案と keep / delete / live-confirm の棚卸しを planning artifact に追加

## In Progress

- PH2 実装: root / child Application の file split 差分を準備
- PH2 実装: `access/**` target path と shared access plane owner を作成

## Blocked

- なし

## Completed This Week

- `tasks/` ディレクトリと PH ドキュメントを作成
- Grafana Cloud / 現行 monitoring stack 完全削除方針を tasks へ反映
- Target Operating Model / contract / PR bot / kubeconform / rehearsal 方針を文書へ反映
- `apps` と `access` の責務分離、runtime/access pair、rendered collision check 方針を文書へ反映
- `roadmap.md` の依存順と gate を新主線へ更新
- policy / legacy inventory / risk を access 抽出前提へ更新
- planning artifact 3 点に実在 component / surface / 固定値の初期入力を追加
- 残論点を `tasks/open-issues.md` に集約し、status から参照可能にした
- OI-001 / OI-002 / OI-003 / OI-005 を解消し、PH0 の canonical owner / surface / contract 境界を固定した
- OI-004 / OI-006 を解消し、PH2 の access owner 粒度・抽出順・dead path 方針を固定した
- `external-secret-split-plan.md` を追加し、`manifests/platform/secrets/external-secrets/` の target-state file split、legacy Secret、live-confirm 候補を具体化した

## Next Gate

- Gate PH2: target topology 実装完了、旧 owner 参照更新、empty dir / dead path 除去の完了

## Open Decisions

- なし

## Notes

- main ブランチに旧新併存を残さない
- `apps/` は workload-only、公開/接続系は `access/` に分離する
- 各サービスは `runtime + access` の pair を持てるが、それ以外の owner 分割は禁止する
- owner 一意性の最終担保は rendered resource collision check とする
- cutover 時の停止時間は許容（snapshot / rollback 前提）
- Harbor / RustFS は `rebuildable-stateful` として clean rebuild を許容する
- `manifests/bootstrap/**` の `targetRevision: HEAD` は repo 既知条件に従う恒久許容であり、一時例外として扱わない
- `prune:false` は allowlist 管理し、例外台帳で常態化させない
- PH5 / PH6 の公式 pass/fail 判定は `automation/scripts/ci/validate.sh` を正とする
- `validate.sh` への `policy-check.sh` / `kubeconform` 組み込みは PH5 の実装対象であり、現時点では方針確定まで完了
- 公式 bootstrap 入口の専用 alias（`make bootstrap` / `automation/scripts/run.sh bootstrap`）は PH1 の実装対象であり、現行 `phase3` とは別物として扱う
- `make bootstrap` / `run.sh bootstrap` を含む記述は PH1 実装後の target state を指し、現行 repo の即時実行手順ではない
- `nix develop .#bootstrap` はローカル operator toolchain shell、`make bootstrap` / `automation/scripts/run.sh bootstrap` は GitOps bootstrap 入口であり、別物として扱う
- Nix はローカル CLI toolchain の再現を担い、`sudo` / `systemd` / `libvirt` / KVM / Docker daemon は引き続き Ubuntu host 側の責務とする
- Grafana Cloud と現行 `monitoring` stack は PH6 で完全削除する legacy として扱い、代替監視基盤は `tasks/backlog.md` で別管理する
- `sandbox-config` の target owner は `bootstrap/applications/platform/sandbox-config`、target path は `manifests/platform/shared-config/sandbox/` とする
- app 固有の非機密設定は runtime owner path の owner-local configuration に残し、複数 workload で共有する値だけを `platform/shared-config` へ昇格させる
- access URL は独立 contract key を持たず、canonical surface ID と scheme から導出する
- `access` owner は `service access` と `shared access plane` の 2 層に固定し、`Gateway` resource / listener 基盤は `gateway-shared` が持つ
- empty dir / dead path は reservation せず削除する
