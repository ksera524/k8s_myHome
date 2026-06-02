# リスク台帳

## 使い方

- 重大度: High / Medium / Low
- 状態: Open / Mitigating / Closed
- すべての Open リスクに対策担当を持つ
- 期限切れリスクは status でブロッカーとして扱う

## リスク一覧

| ID | リスク | 重大度 | 状態 | Owner | 期限 | 対策方針 |
|---|---|---|---|---|---|---|
| R-001 | bootstrap 分離中に ArgoCD 同期順が崩れる | High | Closed | platform | PH1 完了 | `make bootstrap` を ArgoCD 初期導入、pre-ESO Secret、root Application 適用に限定し、steady-state 同期判断を child Application へ戻した |
| R-002 | 旧仕様の完全削除時に一時停止が長引く | High | Open | infra | PH6 cutover 前 | snapshot と rollback 手順を事前確立し、disposable rehearsal 環境で cutover rehearsal / rollback rehearsal を実施 |
| R-003 | 固定 IP/DNS の置換漏れが発生する | High | Closed | network | PH4 完了 | `cluster-contract.yaml` / `access-surfaces.yaml`、inventory、contract-aware check、変更手順 docs で追跡と drift 検出を固定済み |
| R-004 | topology 正規化後に planning / audit / cutover inventory が current repo に追従漏れする | High | Closed | gitops | PH2 完了 | planning artifact と `weekly-version-audit.yml` を current topology へ同期し、monitoring legacy は PH6 delete scope として切り分け済み |
| R-005 | app delivery から `kubectl` を除去した際に運用手順が破綻する | Medium | Closed | app-platform | PH3 完了 | runner 自動生成、generated workflow、shared Secret 読み取り、Deployment patch 権限を削除し、`1 app / 1 image update / 1 infra PR` 契約と runtime/access PR 分離を docs に反映済み |
| R-006 | policy fail 導入で既存 PR が大量失敗する | Medium | Closed | ci | PH5 完了 | allowlist / exception register / `kubeconform` skip list を固定し、Dockerized Nix 上の `validate.sh` green を確認済み |
| R-007 | docs 更新漏れで旧手順が再流入する | Medium | Closed | docs | PH6 repo cleanup 完了 | PH6 repo-side cleanup で docs / diagram / manifests README の monitoring legacy を削除し、旧 path 再流入は policy で fail-closed にした |
| R-008 | Harbor/RustFS の clean rebuild 時に PVC や NFS archive が中途半端に残り、再作成後の状態が不定になる | Medium | Open | storage | PH6 cutover 前 | `rebuildable-stateful` の delete scope（Namespace/PVC/NFS archive/Secret）を事前に固定し、実施後の確認項目を cutover checklist に追加 |
| R-009 | Grafana Cloud と現行 monitoring stack を削除した後、代替監視導入までの間に可観測性が不足する | Medium | Open | platform | PH6 cutover 前 | PH6 では monitoring stack 削除を優先し、最低限の cutover 監視は `tasks/cutover-checklist.md` を正本とする観測面で代替する。`make phase5` は `verify.sh` が target-state 化された後にのみ補助シグナルとして使う。代替監視基盤は backlog で別管理する |
| R-010 | Nix devShell と host prerequisite の責務が混同され、fresh PC bootstrap で libvirt / systemd / Docker 依存を見落とす | Medium | Closed | infra | PH1 完了 | `flake.nix` と `setup-host.sh` Nix-aware mode で CLI と host prerequisite の境界を固定済み |
| R-011 | Gateway / Cloudflared / CoreDNS / Tailscale Split DNS の access surface 定義がずれ、公開経路が部分的に壊れる | High | Closed | network | PH4 完了 | `contract-check.py` で hostname / listener / backend / Cloudflared / CoreDNS / Tailscale Split DNS の drift 検出を `validate.sh` に組み込み済み |
| R-012 | `apps` から `access` への抽出過程で rendered resource collision や orphan route が発生する | High | Closed | gitops | PH2 完了 | access 抽出後の tracked path / child Application 構造を確認済み。rendered collision check の恒久化は PH5 の R-009 へ引き継ぐ |
| R-013 | Nix / toolchain 整備の support lane が PH1 主線を圧迫し、bootstrap 最小化が後回しになる | Medium | Closed | infra | PH1 完了 | bootstrap 最小化を先に実装し、`flake.lock` 生成は PH5 toolchain pinning へ引き継いだ |
| R-014 | `access` 専用 `AppProject` を固定しないまま path だけ分離し、ArgoCD 権限境界が現行の重複状態を引きずる | High | Closed | gitops | PH2 完了 | `core` / `infrastructure` / `platform` / `access` / `apps` の 5 系統 AppProject と `access` child Application の `project: access` を確認済み |
