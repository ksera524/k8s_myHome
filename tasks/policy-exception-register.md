# ポリシー例外台帳

## 目的

- `HEAD` / `latest` / `prune:false` などの例外運用を可視化する
- 例外を無期限化させず、owner と期限で管理する

## 運用ルール

1. 例外は PR で明示し、この台帳へ同時登録する
2. 期限なし例外は禁止
3. 期限到来時に更新または削除の判断を必ず行う
4. CI は「禁止」項目を fail、「例外登録済み」を pass する
5. PH6 完了条件では legacy 関連例外（旧仕様削除を妨げる例外）を Open 0 件にする

## 区分

- `禁止`: 原則使用不可。検出時は CI fail
- `条件付き許容`: 用途・場所を限定して許容
- `例外`: 台帳登録された一時許容

## 例外一覧

| ID | ルールID | 区分 | 対象 | 理由 | Owner | 期限 | 除去条件 | Legacy影響 | 状態 |
|---|---|---|---|---|---|---|---|---|---|
| EX-001 | R-006 | 例外 | `manifests/bootstrap/app-of-apps.yaml` の `targetRevision: HEAD` | bootstrap 追従性を優先 | gitops | 2026-08-31 | pinned revision 戦略を確定して置換 | No | Open |
| EX-002 | R-006 | 例外 | `manifests/bootstrap/app-of-apps.yaml` の `prune: false`（限定リソース） | 誤削除回避が必要なパッチ運用 | platform | 2026-08-31 | 代替安全策（sync option）確立後に削除 | No | Open |

## メモ

- first-party workloads の `:latest` は例外対象にしない（PH3 で廃止対象）
- third-party image tag は別途 version 管理方針に従う
