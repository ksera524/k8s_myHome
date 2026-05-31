# ポリシー例外台帳

## 目的

- `HEAD` / `latest` / `prune:false` などの例外運用を可視化する
- 例外を無期限化させず、owner と期限で管理する

## 運用ルール

1. 例外は PR で明示し、この台帳へ同時登録する
2. 期限なし例外は禁止
3. 期限到来時に更新または削除の判断を必ず行う
4. CI は「禁止」項目と条件違反を fail し、例外可のルールに限って「例外登録済み」を pass する
5. PH6 完了条件では legacy 関連例外（旧仕様削除を妨げる例外）を Open 0 件にする
6. `manifests/bootstrap/**` の `targetRevision: HEAD` と allowlisted `prune:false` は条件付き許容であり、例外登録対象にしない
7. 例外照合キーは `rule_id + file_path + document identity + field_path` とする

## 区分

- `禁止`: 原則使用不可。検出時は CI fail
- `条件付き許容`: 用途・場所を限定して許容
- `例外`: 台帳登録された一時許容

## 例外一覧

| ID | ルールID | 区分 | 対象ファイル | Document | Field | 理由 | Owner | 期限 | 除去条件 | Legacy影響 | 状態 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| （なし） | - | - | - | - | - | - | - | - | - | - | - |

## メモ

- `harbor.qroksera.com/sandbox/*:latest` は `manifests/apps/` 配下かつ workload namespace が `sandbox` の場合のみ条件付き許容であり、例外登録対象にしない
- `manifests/bootstrap/**` の `targetRevision: HEAD` は repo 既知条件に基づく条件付き許容であり、例外登録対象にしない
- `allowlisted prune:false` も条件付き許容であり、例外登録対象にしない
- 例外登録が必要な場合、`Document` は `kind/namespace/name` または `kind/name` 形式、`Field` は `spec.source.targetRevision` のような dot path で記録する
- 非 `sandbox` namespace の first-party workload に対する `:latest` は禁止とし、例外でも許可しない
- third-party image tag は別途 version 管理方針に従う
