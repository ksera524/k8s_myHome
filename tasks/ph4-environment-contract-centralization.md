# PH4: Environment and Access Contract Centralization

## 目的

- 環境固有値（IP/DNS/StorageClass 等）の正本を一元化し、ドリフトを抑止する
- hostname / access surface の正本を一元化し、公開経路の二重管理をなくす
- 非機密 contract と secret/local 設定を分離し、変更経路を明確化する

## 背景

- 固定値が `automation/` と `manifests/` に分散し、変更時の漏れが起きやすい
- hostname / listener / DNS / tunnel / backend の対応が複数箇所に分散している

## スコープ

- 環境契約ファイルの定義
- access surface 契約ファイルの定義
- 値の棚卸しと移行計画
- 参照ルール統一
- 生成/反映/検証の運用方式定義
- Grafana Cloud endpoint / token / ExternalSecret の target-state からの除去

## 正本モデル

1. 非機密 environment contract の正本は `manifests/contracts/home-lab/cluster-contract.yaml` とし、必要なら `manifests/contracts/home-lab/fragments/*.yaml` に分割する
2. `cluster-contract.yaml` は domain base、CIDR、node/service IP、StorageClass、NFS などの infra 基盤値だけを持ち、surface 固有の hostname / listener / publish は持たない
3. 非機密 access contract の正本は `manifests/contracts/home-lab/access-surfaces.yaml` とし、surface entry と shared access-plane metadata（例: Cloudflared tunnel ID）を必要に応じて配下 fragment と合わせて管理する
4. access URL / host alias / auth host のような surface 由来値は原則 `access-surfaces.yaml` の surface ID と scheme、および `cluster-contract.yaml` の infra 基盤値から導出し、独立した cluster contract key は作らない
5. runtime owner 内の automation / CronJob / maintenance job が使う in-cluster Service endpoint は access surface と区別し、原則 contract key を作らず owner local configuration として扱う
6. app 固有の非機密設定は runtime owner path を正本とし、contract / shared-config / secret へ昇格させない
7. 複数 workload が共有するが access surface ではない非機密設定は `manifests/platform/shared-config/**` を正本とする
8. secret / local 設定の正本は `automation/settings.toml` と ESO の参照元に限定し、同じ値を contract に重複させない
9. Kustomize 管理ディレクトリは `configMapGenerator` / `replacements` を優先して contract を反映する
10. Helm Application または repo-local wrapper 配下の chart owner は `valueFiles` または明示的 values fragment を経由して contract を参照する
11. raw manifest は contract 注入のために Kustomize wrapper を追加してから移行する。直書きを残す場合は例外条件と除去期限を文書化する
12. `Gateway`, `Cloudflared`, `CoreDNS`, `Tailscale Split DNS` など access owner は `access-surfaces.yaml` に定義された surface と shared metadata だけを扱う

## 非ゴール

- マルチ環境同時対応

## 具体タスク

1. 環境固有値の棚卸し（IP, DNS, domain, storage, infra endpoints）
2. access surface の棚卸し（hostname, listener, backend, tunnel, DNS publish）
3. 非機密 contract 正本を `manifests/contracts/home-lab/cluster-contract.yaml` に固定する
4. access contract 正本を `manifests/contracts/home-lab/access-surfaces.yaml` に固定する
5. secret/local 設定の正本を `automation/settings.toml` と ESO の参照元に限定する
6. `manifests/` 側の参照方式を Kustomize `replacements` / Helm `valueFiles` / fragment で統一する
7. `app-of-apps.yaml` / child Application / 関連 manifest に残る inline values をファイル参照へ分解する
8. CoreDNS / Harbor / Gateway / Tailscale / NFS / RustFS / Cloudflared / ArgoCD の移行優先順位を決定し、Harbor cleanup CronJob のような runtime-local endpoint は contract key にしない
9. app 固有の非機密設定と shared app config を棚卸しし、どこまでを runtime owner path に残し、どこからを `manifests/platform/shared-config/**` へ昇格させるかを分類する
10. `sandbox-config` のような shared app config を `manifests/platform/shared-config/**` へ再配置する方針を確定する
11. `external-secret-resources.yaml` の monolith 解消方針を定義し、secret domain 単位の分割方針を整理する
12. `ExternalSecret` inventory を `Harbor`、`GitHub/ARC`、`ArgoCD`、`networking`、`app-runtime`、`legacy-monitoring` の論理 secret domain に分類し、keep / merge / delete / live-confirm を決める
13. 同一 `remoteRef.key` から派生する Secret は consumer と format 差分の必要性を確認し、用途差がない duplicate を増やさない方針を定義する
14. Namespace 複製が必要な Secret は consumer と owner を明記し、実在 consumer が確認できる namespace のみを残す
15. `harbor-auth` / `github-auth` のような旧 automation 互換 Secret を PH3/PH6 の legacy 削除対象として分類し、steady-state 正本から外す
16. `ghcr-nginx-charts-secret` / `github-repo-secret` / `harbor-registry` の `default` / `argocd` copy のように repo だけでは未使用断定できないものを live-confirm 候補として分離する
17. 置換漏れ検出用チェックリストを作成する
18. 例外的に固定値を許容する条件を明文化する
19. Grafana Cloud endpoint（`grafana.net`）と Grafana Cloud token を非機密 contract / secret 正本から除去する計画を定義する
20. `grafana-cloud-monitoring` / `grafana-cloud-credentials` / `promtail-grafana-cloud-config` の ESO 依存を target-state から除去する
21. access URL を独立 key にせず surface から導出するルールを docs / inventory / validation に反映する

補足: 上記の secret domain は分類用の論理単位であり、target directory 構成の正本は `external-secret-split-plan.md` を参照する。

## 変更対象

- `automation/settings.toml*`
- `automation/scripts/settings-loader.sh`
- `manifests/infrastructure/`
- `manifests/platform/`
- `manifests/access/`
- `manifests/apps/`
- `manifests/bootstrap/app-of-apps.yaml`
- `manifests/bootstrap/applications/`
- `manifests/contracts/`
- `automation/templates/`
- `docs/kubernetes-architecture.md`
- `docs/manifest-layout.md`
- `tasks/environment-contract-inventory.md`
- `tasks/access-surface-matrix.md`
- `tasks/external-secret-split-plan.md`
- `tasks/legacy-removal-inventory.md`

## 検証

1. 主要環境値が 1 か所から追跡できること
2. 主要 hostname / access surface が 1 か所から追跡でき、URL が surface から導出可能であること
3. 置換漏れ検出チェックで差分が把握できること
4. 非機密 contract と secret/local 設定が混在していないこと
5. target-state の contract / secret 正本に Grafana Cloud endpoint / token が残っていないこと
6. secret domain ごとに keep / merge / delete / live-confirm の分類根拠が追跡できること
7. top-level `ExternalSecret` が `manifests/platform/secrets/external-secrets/**` にしか存在せず、pre-ESO path に残っていないこと
8. 同一 credential が用途根拠なしに別 format / 別 namespace へ重複定義されていないこと

## 完了条件

1. 環境契約の正本が定義済み
2. access 契約の正本が定義済み
3. 主要コンポーネント（child Application を含む）が正本ベースに移行済み
4. ハードコード許容例外が文書化済み
5. 値変更時の作業手順が明記されている
6. `settings.toml` は secret/local 設定の責務に限定されている
7. hostname ごとに owner と access contract entry / cluster contract ref が一意に追跡できる
8. Grafana Cloud endpoint / token / ExternalSecret が target-state の contract / secret 正本から除去対象として固定されている
9. access URL / host alias / auth host のような派生値が独立 key ではなく surface + infra 基盤値から説明でき、runtime-local endpoint は contract 外の owner local configuration として整理されている
10. app 固有の非機密設定が runtime owner path の owner-local configuration として整理され、secret / shared-config / contract へ誤分類されていない
11. shared app config が `manifests/platform/shared-config/**` に分類され、contract へ昇格しない境界が明文化されている
12. Secret inventory が secret domain 単位で分類済みで、duplicate / legacy / live-confirm 候補が keep / merge / delete / live-confirm のいずれかに判定済みである
13. pre-ESO path に top-level `ExternalSecret` が残っていない
14. 旧 automation 互換 Secret と stale secret template の target-state での扱いが PH3 / PH6 へ接続済みである

## 実装結果

- 完了日: 2026-06-02
- 非機密 cluster contract は `manifests/contracts/home-lab/cluster-contract.yaml` に固定済み
- 非機密 access contract は `manifests/contracts/home-lab/access-surfaces.yaml` に固定済み
- `HTTPRoute`, `Gateway`, Cloudflared, CoreDNS, Tailscale Split DNS は contract annotation と `automation/scripts/ci/contract-check.py` で drift 検出済み
- 値変更手順とハードコード許容例外は `docs/environment-contracts.md` に固定済み
- `ExternalSecret` は `manifests/platform/secrets/external-secrets/**` の domain directory に分割済み
- `platform/argocd-config/**` の top-level `ExternalSecret` は 0 件
- Grafana Cloud / monitoring legacy secret は target-state secret 正本から除外済み。monitoring stack 本体の削除は PH6 delete scope として維持する
- PH4 完了状態で `automation/scripts/ci/validate.sh` は green

## 完了記録

- 判定日: 2026-06-02
- 判定: Gate PH4 passed
- 検証コマンド: `automation/scripts/ci/validate.sh`
- 検証結果: green
- 次フェーズ: PH1 Bootstrap Minimalization

### Gate PH4 判定

| 完了条件 | 判定 | 証跡 |
|---|---|---|
| 環境契約の正本が定義済み | Pass | `manifests/contracts/home-lab/cluster-contract.yaml` |
| access 契約の正本が定義済み | Pass | `manifests/contracts/home-lab/access-surfaces.yaml` |
| 主要コンポーネントが正本ベースに移行済み | Pass | access annotation と `automation/scripts/ci/contract-check.py` |
| ハードコード許容例外が文書化済み | Pass | `docs/environment-contracts.md` |
| 値変更時の作業手順が明記されている | Pass | `docs/environment-contracts.md` |
| `settings.toml` は secret/local 設定の責務に限定 | Pass | contract と secret 正本を分離し、secret は ESO 参照元 / local settings に限定 |
| hostname ごとの owner / contract entry が追跡可能 | Pass | `access-surfaces.yaml`, access annotation, `access-surface-matrix.md` |
| Grafana Cloud endpoint / token / ExternalSecret が target-state から除外済み | Pass | Grafana Cloud ExternalSecret を root `kustomization.yaml` から除外し削除対象化 |
| 派生値と runtime-local endpoint の境界が整理済み | Pass | `environment-contract-inventory.md`, `docs/environment-contracts.md` |
| app 固有の非機密設定が owner-local として整理済み | Pass | `environment-contract-inventory.md` |
| shared app config の境界が明文化済み | Pass | `docs/manifest-layout.md`, `docs/environment-contracts.md` |
| Secret inventory が domain 単位で分類済み | Pass | `external-secret-split-plan.md` と domain split 実装 |
| pre-ESO path に top-level `ExternalSecret` が残っていない | Pass | `automation/scripts/ci/consistency-check.sh` |
| 旧 automation 互換 Secret / stale template の扱いが後続 PH に接続済み | Pass | `external-secret-split-plan.md`, PH6 delete scope |

### PH5 / PH6 Handoff

- PH5: `contract-check.py` と `consistency-check.sh` の advisory / required ルールを policy rule set へ統合する。
- PH6: monitoring stack 本体、Grafana chart、monitoring namespace 前提を delete scope として処理する。
- PH6: 旧 automation 互換 secret template の残存 grep と live-confirm 対象の最終削除判定を行う。
