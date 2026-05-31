# リスク台帳

## 使い方

- 重大度: High / Medium / Low
- 状態: Open / Mitigating / Closed
- すべての Open リスクに対策担当を持つ
- 期限切れリスクは status でブロッカーとして扱う

## リスク一覧

| ID | リスク | 重大度 | 状態 | Owner | 期限 | 対策方針 |
|---|---|---|---|---|---|---|
| R-001 | bootstrap 分離中に ArgoCD 同期順が崩れる | High | Open | platform | PH1 完了まで | PH1 で pre/post 依存を明示し smoke test を追加 |
| R-002 | 旧仕様の完全削除時に一時停止が長引く | High | Open | infra | PH6 cutover 前 | snapshot と rollback 手順を事前確立し、disposable rehearsal 環境で cutover rehearsal / rollback rehearsal を実施 |
| R-003 | 固定 IP/DNS の置換漏れが発生する | High | Open | network | PH4 完了まで | PH4 で棚卸し一覧を作り、置換チェックと grep 検証を実施 |
| R-004 | topology 正規化後に planning / audit / cutover inventory が current repo に追従漏れする | High | Open | gitops | PH2 完了まで | PH2 で planning artifact と `weekly-version-audit.yml` を同期し、monitoring legacy は PH6 delete scope として切り分ける |
| R-005 | app delivery から `kubectl` を除去した際に運用手順が破綻する | Medium | Open | app-platform | PH3 完了まで | `1 app / 1 image update / 1 infra PR` 契約と onboarding を先に整備し、`kubectl` フォールバックを禁止した上で切替 |
| R-006 | policy fail 導入で既存 PR が大量失敗する | Medium | Open | ci | PH5 完了まで | allowlist / exception register / `kubeconform` skip list を先に固定し、warn -> fail の段階導入を実施 |
| R-007 | docs 更新漏れで旧手順が再流入する | Medium | Open | docs | PH6 完了まで | PH6 で grep ベースの残存検証を完了条件にする |
| R-008 | Harbor/RustFS の clean rebuild 時に PVC や NFS archive が中途半端に残り、再作成後の状態が不定になる | Medium | Open | storage | PH6 cutover 前 | `rebuildable-stateful` の delete scope（Namespace/PVC/NFS archive/Secret）を事前に固定し、実施後の確認項目を cutover checklist に追加 |
| R-009 | Grafana Cloud と現行 monitoring stack を削除した後、代替監視導入までの間に可観測性が不足する | Medium | Open | platform | PH6 cutover 前 | PH6 では monitoring stack 削除を優先し、最低限の cutover 監視は `tasks/cutover-checklist.md` を正本とする観測面で代替する。`make phase5` は `verify.sh` が target-state 化された後にのみ補助シグナルとして使う。代替監視基盤は backlog で別管理する |
| R-010 | Nix devShell と host prerequisite の責務が混同され、fresh PC bootstrap で libvirt / systemd / Docker 依存を見落とす | Medium | Open | infra | PH1 完了まで | PH1 で `nix develop .#bootstrap` と host prerequisite の責務境界を文書化し、`setup-host.sh` の skip 対象を CLI のみに限定する |
| R-011 | Gateway / Cloudflared / CoreDNS / Tailscale Split DNS の access surface 定義がずれ、公開経路が部分的に壊れる | High | Open | network | PH4 完了まで | `access-surface-matrix.md` と `access-surfaces.yaml` を正本にし、PH5 で contract 未登録 hostname と publication mismatch を検出する |
| R-012 | `apps` から `access` への抽出過程で rendered resource collision や orphan route が発生する | High | Open | gitops | PH2 完了まで | PH2 で暫定チェックを実施し、PH5 で rendered collision check を恒久化する |
| R-013 | Nix / toolchain 整備の support lane が PH1 主線を圧迫し、bootstrap 最小化が後回しになる | Medium | Open | infra | PH1 完了まで | PH1 では bootstrap 最小責務を主線、Nix は support lane として優先順位を分離して管理する |
| R-014 | `access` 専用 `AppProject` を固定しないまま path だけ分離し、ArgoCD 権限境界が現行の重複状態を引きずる | High | Open | gitops | PH2 完了まで | PH2 で `core` / `infrastructure` / `platform` / `access` / `apps` の 5 系統 AppProject を定義し、`access` child Application の `sourceRepos` / `destinations` を最小権限で固定する |
