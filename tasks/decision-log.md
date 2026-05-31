# 設計判断ログ

## 使い方

- 重要判断ごとに 1 エントリ追加
- 変更理由・影響・代替案を残す
- 後から覆した場合も履歴を消さず追記する

## Entries

### DEC-0001: 構造改革フェーズ管理を `tasks/` に集約

- 日付: 2026-05-29
- 状態: accepted
- 背景: 改革タスクが docs/運用メモに分散し、全体進行が追いにくい
- 判断: `tasks/` を構造改革専用として新設し、roadmap/status/PH ドキュメントを集約
- 影響: 進行管理の正本が明確化。運用メモは `docs/tasks/` に分離維持
- 代替案: 既存 `docs/tasks/` に統合（不採用: 運用テーマとの混在が増えるため）

### DEC-0002: 構造改革は `PH0..PH6` で管理

- 日付: 2026-05-29
- 状態: accepted
- 背景: 既存 `make phase1..5` と改革工程の名前衝突を避けたい
- 判断: 改革管理フェーズを `PH0..PH6` に固定
- 影響: 実行フェーズ（make）と管理フェーズ（改革）を明確に区別できる
- 代替案: 既存 phase 名の再利用（不採用: 誤解と運用事故のリスクが高い）

### DEC-0003: 旧仕様は最終的に完全削除し、main に旧新併存を残さない

- 日付: 2026-05-29
- 状態: accepted
- 背景: 互換レイヤを残す運用は責務境界を曖昧化し、事故調査を困難にする
- 判断: cutover 時点で旧仕様を削除し、main には新仕様のみを残す
- 影響: 移行時の停止時間は増えるが、運用複雑性を恒久的に削減できる
- 代替案: 段階併存（不採用: 旧仕様再流入と運用分岐のリスクが高い）

### DEC-0004: `user-applications` / `user-application-definitions` は廃止する

- 日付: 2026-05-29
- 状態: accepted
- 背景: apps の owner が二重化し、どこを正本に見るべきか不明瞭だった
- 判断: apps の owner は root Application 配下の child Application 群へ一本化する
- 影響: bootstrap・verify・audit・docs の参照先更新が必要になる
- 代替案: 集約 Application 継続（不採用: 所有重複が残る）

### DEC-0005: app delivery は PR/commit 経由のみとし、cluster 直接変更を禁止する

- 日付: 2026-05-29
- 状態: accepted
- 背景: runner/workflow からの `kubectl` 操作は責務逸脱と監査困難を生む
- 判断: app delivery は「image push -> infra repo PR」で完結させる
- 影響: `add-runner` 系と workflow 自動生成は削除対象になる
- 代替案: runner 経由の直接 rollout（不採用: 責務境界に反する）

### DEC-0006: 環境依存値は「非機密 contract」と「secret/local 設定」に分離する

- 日付: 2026-05-29
- 状態: accepted
- 背景: `settings.toml` と manifests 双方へのハードコードがドリフトを招いていた
- 判断: 非機密値は Git 管理 contract に集約し、秘密値は local/ESO に限定する
- 影響: manifests の参照方式（values/patch/replacements）を再設計する必要がある
- 代替案: 現行混在維持（不採用: 変更漏れリスクが高い）

### DEC-0007: ポリシー違反は例外台帳なしに許可しない

- 日付: 2026-05-29
- 状態: accepted
- 背景: `HEAD` / `latest` / `prune:false` は一律禁止できないが、無秩序許容も危険
- 判断: 例外は `policy-exception-register.md` に owner/期限付きで登録する
- 影響: CI で「禁止」「条件付き」「例外」の3区分運用が必要になる
- 代替案: 口頭合意（不採用: 継続運用で崩壊する）

### DEC-0008: `sandbox` namespace の first-party workload は `:latest` を条件付き許容する

- 日付: 2026-05-30
- 状態: accepted
- 背景: `sandbox` 配下は実験場であり、固定 tag 強制よりも反復速度を優先したい
- 判断: `harbor.qroksera.com/sandbox/*:latest` は `manifests/apps/` 配下かつ workload namespace が `sandbox` の場合のみ条件付き許容とする
- 影響: PH3/PH5/PH6 は「`latest` 全廃」ではなく「非 `sandbox` では禁止、`sandbox` では条件付き許容」へ更新が必要
- 代替案: first-party workload の `:latest` 一律禁止（不採用: 実験用途の開発速度を不必要に落とす）

### DEC-0009: Harbor と RustFS は PH6 cutover で clean rebuild 可能な `rebuildable-stateful` として扱う

- 日付: 2026-05-30
- 状態: accepted
- 背景: Harbor image と RustFS 上のファイル消失は許容でき、移行簡素化を優先したい
- 判断: Harbor と RustFS は data preservation を必須要件にせず、PH6 では Namespace/PVC/NFS archive/Secret の削除範囲を定義した上で clean rebuild を許容する
- 影響: backup 必須要件は VM snapshot / etcd snapshot 中心に再定義し、Harbor/RustFS の delete scope を cutover checklist に追加する必要がある
- 代替案: Harbor/RustFS の完全バックアップを必須化（不採用: 今回の運用許容度に対して過剰で、cutover を不必要に複雑化する）

### DEC-0010: `manifests/bootstrap/**` の `targetRevision: HEAD` は恒久許容ルールとする

- 日付: 2026-05-30
- 状態: accepted
- 背景: repo の既知条件として `manifests/bootstrap/**` は `HEAD` 維持が必要であり、一時例外扱いにすると PH5 policy が自己矛盾する
- 判断: Git source の `targetRevision: HEAD` は `manifests/bootstrap/**` に限って条件付き許容し、例外台帳の対象にしない
- 影響: PH5 `R-006` は bootstrap allowlist として実装し、bootstrap 以外の `HEAD` だけを review / exception 対象とする
- 代替案: bootstrap も pinned revision へ統一（不採用: 現行 repo / CI 条件と衝突する）

### DEC-0011: PH6 cutover 前に disposable rehearsal を必須化する

- 日付: 2026-05-30
- 状態: accepted
- 背景: main に旧新併存を残さない単発 cutover では、live 本番だけで検証する運用は停止長期化リスクが高い
- 判断: pre-cutover snapshot から復元した disposable rehearsal 環境または同等 clone で end-to-end rehearsal を実施し、成功しない限り PH6 Go 判定を出さない
- 影響: cutover checklist に rehearsal 成功条件と rollback rehearsal 記録が必須になる
- 代替案: live cutover のみで進める（不採用: rollback 判断の材料が不足する）

### DEC-0012: 非機密 environment contract の正本は `manifests/contracts/home-lab/cluster-contract.yaml` とする

- 日付: 2026-05-30
- 状態: accepted
- 背景: IP / DNS / endpoint / StorageClass が `automation/` と `manifests/` に分散し、変更漏れを起こしていた
- 判断: 非機密値は `manifests/contracts/home-lab/cluster-contract.yaml` を正本とし、必要に応じて同配下 fragment に分割する。secret / local 値は `automation/settings.toml` と ESO 側に残す
- 影響: PH4 は manifest 参照を contract 起点へ寄せ、ハードコードは例外理由つきでのみ許容する
- 代替案: 既存ファイルごとの個別管理を継続（不採用: 追跡性が低い）

### DEC-0013: app delivery の PR 単位は `1 app / 1 image update / 1 infra PR` とする

- 日付: 2026-05-30
- 状態: accepted
- 背景: image 更新と infra 変更が混ざるとレビュー範囲と rollback 単位が曖昧になる
- 判断: app repo workflow または release bot は image push 後に infra repo へ app 単位の PR を作成し、変更面は `manifests/apps/<app>/` または app 専用 values のみに限定する
- 影響: PH3 の review / audit / rollback 粒度が固定され、`kubectl` 直接変更の代替経路が明確になる
- 代替案: 複数 app 一括 PR または cluster 直接変更（不採用: 影響範囲が広すぎる）

### DEC-0014: schema 検証は `kubeconform` を採用し、CRD 系は allowlist / skip list で段階導入する

- 日付: 2026-05-30
- 状態: accepted
- 背景: `yamllint` と `kustomize build` だけでは API schema の破綻を十分に拾えない
- 判断: PH5 で `kubeconform` を追加し、CRD が多い箇所は allowlist / skip list を明示して段階的に fail へ移行する
- 影響: `validate.sh` 拡張時に schema 例外管理が必要になるが、fail 条件が明文化される
- 代替案: schema 検証を導入しない（不採用: cutover 前の静的保証が不足する）

### DEC-0015: `validate.sh` を唯一の公開判定入口とし、`policy-check.sh` は内部実装に分離する

- 日付: 2026-05-30
- 状態: accepted
- 背景: `policy check` を独立した公開判定入口にすると CI / rehearsal / cutover の pass/fail 判定が分岐しやすい
- 判断: `automation/scripts/ci/validate.sh` を唯一の公開判定入口とし、`automation/scripts/ci/policy-check.sh` は `validate.sh` から呼び出される内部実装として扱う
- 影響: PH5 / PH6 / cutover checklist は `validate.sh` 成功を正本判定に統一する
- 代替案: `policy-check.sh` を `validate.sh` と並列の公開入口にする（不採用: 運用判断が分岐する）

### DEC-0016: PH3 の PR bot 認証方式は GitHub App を標準とする

- 日付: 2026-05-30
- 状態: accepted
- 背景: repo-scoped credential を求める一方で、長寿命 PAT は権限過多とローテーション負荷を招きやすい
- 判断: PH3 の PR bot 認証方式は GitHub App を標準とし、PAT は secret owner 承認付きの暫定例外としてのみ扱う
- 影響: PH3 の運用契約、secret 管理、onboarding 手順は GitHub App 前提で整備する
- 代替案: PAT を標準にする（不採用: 権限境界と運用健全性が劣る）

### DEC-0017: PH6 rehearsal の標準環境は VM snapshot restore による disposable clone とする

- 日付: 2026-05-30
- 状態: accepted
- 背景: single cutover 前提では、本番相当性と復元再現性の高い rehearsal が必要
- 判断: PH6 rehearsal は pre-cutover VM snapshot から復元した disposable clone を標準とし、同等 clone は代替手段としてのみ扱う
- 影響: `status.md` の rehearsal 環境論点は解消し、cutover 前提は snapshot restore clone 基準で計画する
- 代替案: 同一環境 dry-run または ad-hoc clone（不採用: 再現性と rollback 検証が弱い）

### DEC-0018: app owner 重複検出は structural rule として実装する

- 日付: 2026-05-30
- 状態: accepted
- 背景: raw path 一致ベースの汎用検出では `argocd-projects` と `argocd-core` のような正当ケースを誤検知する
- 判断: PH5 の owner 重複検出は `R-007` として、legacy 集約 owner の禁止と `manifests/bootstrap/applications/user-apps/*.yaml` の一意性に限定した structural rule で実装する
- 影響: PH2 / PH5 の完了条件は app owner 重複の防止に具体化され、path 共有の合法ケースを阻害しない
- 代替案: 汎用 path 重複検出（不採用: 誤検知が多い）

### DEC-0019: `make bootstrap` は GitOps bootstrap 専用入口として新設する

- 日付: 2026-05-30
- 状態: accepted
- 背景: 既存 `phase3` は GitOps Prep を指しており、そのまま bootstrap 完結入口として再解釈すると fresh cluster 手順と PH6 cutover 手順が混同されやすい
- 判断: PH1 で `make bootstrap`（実体: `automation/scripts/run.sh bootstrap`）を新設し、GitOps bootstrap 専用入口とする。fresh cluster では `make phase1 -> make phase2 -> make bootstrap -> make phase5`、PH6 cutover / rehearsal では既存 cluster に対して `make bootstrap` のみを使う
- 影響: PH1 は `run.sh` / `Makefile` / docs の実行境界を同時更新し、PH6 checklist は `phase1` / `phase2` 再実行を含まない cutover 手順として固定できる
- 代替案: `make phase3` を bootstrap 完結入口として流用（不採用: 現行意味と衝突し誤実行を招く）

### DEC-0020: Grafana Cloud と現行 monitoring stack は構造改革で完全削除する

- 日付: 2026-05-30
- 状態: accepted
- 背景: 現行の `monitoring` Application は `grafana/k8s-monitoring` と Grafana Cloud endpoint / token / ExternalSecret に密結合しており、bootstrap / GitOps topology / secret 管理 / docs / audit に横断的な legacy を残している
- 判断: 構造改革では Grafana Cloud 接続情報だけでなく、`monitoring` Application、`manifests/monitoring/`、Grafana Cloud 用 ExternalSecret、`deploy-grafana-*` スクリプト、version audit、関連 docs を PH6 cutover で完全削除する。PH5 では `grafana` 全面禁止ではなく、現行 legacy 識別子の再流入だけを fail-closed で検出する
- 影響: `tasks/` の PH0/PH1/PH2/PH4/PH5/PH6、legacy removal inventory、cutover checklist、risk/backlog を更新し、代替監視基盤の導入は今回の改革スコープから外して backlog で管理する必要がある
- 代替案: Grafana Cloud のみ削除して `grafana/k8s-monitoring` を温存する（不採用: 現行構成では監視 stack 自体が Grafana Cloud 前提であり、中途半端な残置は責務境界と削除判定を曖昧化する）

### DEC-0021: ローカル operator toolchain の正本は Nix flake とする

- 日付: 2026-05-30
- 状態: accepted
- 背景: 新規 PC で必要 CLI の導入経路が分散しており、`validate.sh` のローカル実行環境も CI とずれやすい
- 判断: `flake.nix` / `flake.lock` をローカル toolchain の正本とし、`devShells.default` は validate / CI 用、`devShells.bootstrap` は fresh host bootstrap 用に使う
- 判断: Linux 前提のため shell 名や wrapper 名に OS prefix は付けず、必要な導線は `bootstrap` / `bootstrap.sh` に固定する
- 判断: Nix は CLI toolchain の再現に限定し、`sudo` / `systemd` / `libvirt` / KVM / Docker daemon などの host prerequisite は Ubuntu host 側の責務として維持する
- 影響: PH1 で local bootstrap shell と `setup-host.sh` の境界を定義し、PH5 で `validate.sh` の実行 toolchain を CI / ローカルで共通化し、PH6 で docs を正式化する
- 代替案: CLI 導入を `apt` / `pip` / 手動バイナリ取得の組み合わせで継続する（不採用: 新規 PC 立ち上げと CI / ローカル整合が崩れやすい）

### DEC-0022: `apps/` は workload-only、公開/接続系は `access/` に分離する

- 日付: 2026-05-30
- 状態: accepted
- 背景: `apps/` 配下に workload と route / tunnel / DNS 公開設定が混在し、owner と review 単位が曖昧になっていた
- 判断: `manifests/apps/**` は workload-only とし、公開/接続系 resource は top-level の `manifests/access/**` に集約する
- 影響: PH2 は access extraction を含む topology 正規化になり、PH5 は `apps/**` への access resource 混入を fail-closed で検出する必要がある
- 代替案: `apps/` 配下に route を残す（不採用: workload と公開面の二重管理が残る）

### DEC-0023: 各サービスの owner モデルは `runtime + access` pair を基本とする

- 日付: 2026-05-30
- 状態: accepted
- 背景: 公開経路を app owner に従属させる案では、Cloudflared / DNS / Gateway の横断責務が吸収しきれない
- 判断: 各サービスは `runtime` と `access` の pair を持てるが、それ以外の owner 分割は禁止する
- 影響: PH0 は split-owner 例外条件を明文化し、PH3 / PH6 は onboarding と docs を pair モデルへ更新する必要がある
- 代替案: service owner が runtime と access をすべて単独所有（不採用: access plane の横断運用と整合しない）

### DEC-0024: owner 一意性は `AppProject destination` ではなく rendered resource collision check で担保する

- 日付: 2026-05-30
- 状態: accepted
- 背景: namespace destination の重複有無だけでは access plane 分離後の owner 一意性を表現できない
- 判断: owner 一意性の最終担保は rendered resource collision check とし、AppProject destination は最小権限の補助境界として扱う
- 影響: PH2 の完了条件と PH5 の policy 実装は structural rule + rendered collision check 前提に更新する必要がある
- 代替案: AppProject destination 制約を主たる owner 判定に使う（不採用: apps/access pair と cluster-scoped resource の扱いに無理がある）

### DEC-0025: hostname / publication の正本は `access-surfaces.yaml` とする

- 日付: 2026-05-30
- 状態: accepted
- 背景: `Gateway`, `Cloudflared`, `CoreDNS`, `Tailscale Split DNS` に hostname が分散し、変更漏れの温床になっていた
- 判断: hostname / listener / backend / tunnel / DNS publish の正本は `manifests/contracts/home-lab/access-surfaces.yaml` とし、各 access owner はそこから参照する
- 影響: PH4 は environment contract だけでなく access contract も扱い、PH5 は contract 未登録 hostname の再流入を検出する必要がある
- 代替案: 各 manifest ごとの個別管理を継続（不採用: 公開経路の追跡性が不足する）

### DEC-0026: `sandbox-config` は platform 配下の shared config owner とする

- 日付: 2026-05-31
- 状態: accepted
- 背景: `manifests/apps/sandbox-config/` は複数 workload から参照される shared config だが、`apps/` workload-only 方針と衝突していた
- 判断: `sandbox-config` の target owner は `bootstrap/applications/platform/sandbox-config`、target path は `manifests/platform/shared-config/sandbox/` とし、user app owner には置かない
- 影響: OI-001 を Close し、PH0/PH2/ownership matrix/contract inventory は shared config 前提へ更新する
- 代替案: `apps/` 配下に残置する、または専用 user app owner を作る（不採用: workload-only 方針と責務分離に反する）

### DEC-0027: internal access surface の canonical ID と DNS publish 責務を固定する

- 日付: 2026-05-31
- 状態: accepted
- 背景: internal surface の backend 名、contract entry、CoreDNS / Tailscale Split DNS の責務が planning artifact 間で未確定に見えていた
- 判断: canonical surface ID は `argocd-internal`, `harbor-internal`, `cooklog-internal`, `api-hub-internal`, `hitomi-upload-viewer-internal` とする。CoreDNS は上記すべてを publish し、Tailscale Split DNS は `cooklog-internal`, `api-hub-internal`, `hitomi-upload-viewer-internal` のみを publish する。`argocd-internal` と `harbor-internal` は CoreDNS-only とする
- 影響: OI-002 を Close し、`access-surface-matrix.md` の internal 行と PH4 access contract 設計を canonical surface ID 前提に統一する
- 代替案: internal host ごとに個別ルールを残す（不採用: publication 責務が追跡しづらい）

### DEC-0028: access URL は独立 contract key を持たず surface から導出する

- 日付: 2026-05-31
- 状態: accepted
- 背景: `https://argocd.qroksera.com` や `https://harbor.qroksera.com` のような URL 文字列が hostname と別 key で散在し、二重管理になっていた
- 判断: access URL は `access-surfaces.yaml` の canonical surface ID と scheme から導出し、独立した cluster contract key は作らない。path / port / scheme override が意味を持つ場合のみ access contract 側で明示する。Cloudflared tunnel ID のような shared access-plane metadata も cluster contract ではなく access contract 側で管理する
- 影響: OI-002/OI-003 の contract 表現を整理でき、`environment-contract-inventory.md` は `derive from access-surfaces.yaml#<surface-id>` 表記に統一される
- 代替案: URL 文字列を hostname と別 key で管理する（不採用: drift を増やす）

### DEC-0029: service IP 命名は `gateway` / `tailscaleSplitDNS` を canonical とし Harbor 専用 LB key は持たない

- 日付: 2026-05-31
- 状態: accepted
- 背景: `gateway LB IP`, `tailscale split DNS LB IP`, `ingress_lb_ip`, `harbor LB IP` の意味が混在し、settings と manifest の対応が分かりにくかった
- 判断: canonical key は `network.serviceIPs.gateway` と `network.serviceIPs.tailscaleSplitDNS` とする。Harbor 外部/内部公開は gateway surface 由来とし、独立した `harbor LB IP` key は作らない。旧 `ingress_lb_ip` は rename/remove 対象として扱う
- 影響: OI-003 を Close し、PH4 は `settings.toml*` と manifest の命名 drift をこの 2 key 起点で解消する
- 代替案: Harbor 専用 LB key を追加する（不採用: gateway 公開面との責務が二重になる）

### DEC-0030: Harbor の split owner 境界を runtime / access / optional ops に固定する

- 日付: 2026-05-31
- 状態: accepted
- 背景: `harbor-patch` には route / client policy / cleanup CronJob / node-mutations が混在し、どこまでを access owner に寄せるか曖昧だった
- 判断: `bootstrap/applications/platform/harbor` が Helm release と Harbor cleanup CronJob を所有し、`bootstrap/applications/access/harbor-access` が `HTTPRoute` / `ClientSettingsPolicy` / hostname publication を所有する。`node-mutations` は steady-state owner ではなく opt-in operational overlay として分離する
- 影響: OI-005 を Close し、PH2/ownership matrix/policy/cutover 文書は `harbor-patch` 固定前提ではなく target runtime/access pair 前提へ更新する
- 代替案: `harbor-patch` を恒久 owner として残す（不採用: runtime/access/ops の責務分離に反する）

### DEC-0031: access extraction は `service access` と `shared access plane` の 2 層で固定する

- 日付: 2026-05-31
- 状態: accepted
- 背景: access resource を service ごとに細かく切りすぎると Cloudflared / DNS / Gateway listener の shared resource owner が曖昧になり、逆に一括 owner に寄せると review 単位が粗くなる
- 判断: access owner は `service access` と `shared access plane` の 2 層で固定する。service access は `argocd-access`, `harbor-access`, `rustfs-access`, `blog-access`, `cooklog-access`, `api-hub-access`, `hitomi-upload-viewer-access` とし、shared access plane は `gateway-shared`, `cloudflared`, `dns-core`, `dns-tailscale` とする。`Gateway` resource / listener 基盤は controller/CRD と分離し、`manifests/access/gateway/` を `gateway-shared` が所有する。child `Application` の粒度は `1 owner / 1 file / 1 path` に固定する
- 影響: OI-004 を Close し、PH2 / ownership matrix / access surface matrix / legacy removal inventory は 2 層 access owner 前提へ更新する
- 代替案: service ごとに Cloudflared / DNS を複製する、または `access` を 1 owner に集約する（不採用: shared resource collision またはレビュー粒度悪化を招く）

### DEC-0032: access extraction の移行順は `shared foundation -> runtime-backed service routes -> publishers -> legacy delete` とする

- 日付: 2026-05-31
- 状態: accepted
- 背景: listener / route / publication を無秩序に移すと、一時的に到達性が壊れたり ownership が追いにくくなる
- 判断: 実装順は 1) `gateway-shared` など shared foundation の target owner / path / child Application を先に定義、2) `blog`, `cooklog`, `api-hub`, `hitomi-upload-viewer` の route を service access へ移す、3) `argocd` / `rustfs` を legacy external app 名から service access owner へ移す、4) Harbor を runtime / access / optional ops に分割する、5) `dns-core`, `dns-tailscale`, `cloudflared` の publisher 定義を shared access plane へ移し、旧 path を同一 change set から除去する、の順とする。sync wave は `infra controllers -> gateway-shared -> runtime owners -> service access owners -> shared publishers` を原則とする
- 影響: PH2 の抽出順と sync wave の議論を固定でき、cutover / verify / policy の review 軸が揃う
- 代替案: publisher を先に移す、または route/publisher を同時に大規模移動する（不採用: 切り戻しとレビューが難しくなる）

### DEC-0033: empty dir / dead path は reservation せず削除する

- 日付: 2026-05-31
- 状態: accepted
- 背景: `manifests/apps/harbor` などの空ディレクトリは owner 候補にも dead path にも見え、GitOps 正本の可読性を下げていた
- 判断: empty dir / dead path は reservation 用に残さず、実体がないものは削除する。将来必要になった時点で、owner と manifest を伴う形で新規追加する
- 影響: OI-006 を Close し、legacy removal inventory と PH2 完了条件は「空ディレクトリが存在しないこと」を前提にする
- 代替案: 予約ディレクトリとして残す（不採用: path の意味が曖昧になり、policy と grep のノイズになる）

### DEC-0034: Harbor cleanup CronJob は access surface ではなく runtime-local endpoint を使う

- 日付: 2026-05-31
- 状態: accepted
- 背景: `harbor-patch` 廃止後も cleanup CronJob が `https://harbor.qroksera.com` を叩くと、runtime owner が `harbor-access` / Gateway / DNS へ逆依存し、runtime/access 境界が崩れる
- 判断: Harbor の sandbox image cleanup / GC CronJob は `platform/harbor` の runtime owner に属し、到達先は `harbor-core.harbor.svc` などの in-cluster Harbor Service とする。`harbor-external` / `harbor-internal` は人間利用や外部クライアント向け access surface としてのみ扱う
- 影響: PH2 / PH3 / PH4 / PH6 文書は cleanup CronJob を access contract から切り離し、runtime-local config として扱う前提へ更新する。cutover / verify では cleanup CronJob の internal reachability を確認する
- 代替案: cleanup CronJob も external URL を使い続ける（不採用: runtime/access の責務分離に反し、Gateway / DNS 障害が runtime ops に波及する）

### DEC-0035: remote chart を含む Harbor runtime owner は repo-local wrapper を正本にする

- 日付: 2026-05-31
- 状態: accepted
- 背景: `platform/harbor` は remote Helm chart と repo 管理の cleanup CronJob を同一 owner が持つ必要があるが、multi-source 例外を増やすと `1 owner / 1 file / 1 path` 原則が崩れる
- 判断: `bootstrap/applications/platform/harbor` は `manifests/platform/harbor/` の repo-local wrapper path を正本とし、その配下で Harbor chart values, runtime-side manifest, contract injection を管理する。child `Application` には Harbor 専用の multi-source 例外を作らない
- 影響: PH2 は Harbor runtime path を wrapper 前提で確定し、PH4 は wrapper への contract 注入方式を設計する。PH6 では `harbor-patch` と旧 `manifests/infrastructure/gitops/harbor` steady-state 入口を削除対象に含める
- 代替案: Harbor だけ multi-source `Application` を恒久許容する（不採用: owner/path 原則の例外が増え、review / policy が複雑化する）

### DEC-0036: app 固有の非機密設定は runtime owner path の owner-local configuration に残す

- 日付: 2026-05-31
- 状態: accepted
- 背景: `home-camera` の RTSP URL や単一 consumer の Selenium endpoint は非機密だが app 固有であり、secret 扱いや shared-config 扱いに寄せると不要な管理経路や責務の膨張を生む
- 判断: app 固有の非機密設定は `manifests/apps/<app>/` または対応する runtime owner path の owner-local configuration として扱い、contract / shared-config / secret へ昇格させない。複数 workload が共有する値だけを `manifests/platform/shared-config/**` へ寄せる
- 影響: `home-camera` は一時的な Secret 化を採らず manifest 直下の owner-local non-secret config として戻す。PH0 / PH4 / policy / inventory / docs は owner-local non-secret config の分類を明示する
- 代替案: 非機密でも Secret に入れる、または shared-config に一律集約する（不採用: 管理経路が増え、shared config の責務が不必要に広がる）
