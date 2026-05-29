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
| R-002 | 旧仕様の完全削除時に一時停止が長引く | High | Open | infra | PH6 cutover 前 | snapshot と rollback 手順を事前確立し、cutover リハーサルを実施 |
| R-003 | 固定 IP/DNS の置換漏れが発生する | High | Open | network | PH4 完了まで | PH4 で棚卸し一覧を作り、置換チェックと grep 検証を実施 |
| R-004 | `user-applications` 廃止後に verify/audit が追従漏れする | High | Open | gitops | PH2 完了まで | PH2 で `platform-deploy.sh`/`verify.sh`/`weekly-version-audit.yml` を同時更新 |
| R-005 | app delivery から `kubectl` を除去した際に運用手順が破綻する | Medium | Open | app-platform | PH3 完了まで | PR bot 方式の運用手順と onboarding を先に整備してから切替 |
| R-006 | policy fail 導入で既存 PR が大量失敗する | Medium | Open | ci | PH5 完了まで | PH5 で warn -> fail の段階導入と例外台帳運用を実施 |
| R-007 | docs 更新漏れで旧手順が再流入する | Medium | Open | docs | PH6 完了まで | PH6 で grep ベースの残存検証を完了条件にする |
