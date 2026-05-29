# PH5: Safety Policy and Validation

## 目的

- 壊れやすい変更を CI/運用ガードで早期検出し、事故を予防する

## 背景

- 静的検証中心で、運用整合性や禁止パターンの検出が弱い

## スコープ

- ポリシー定義
- CI 検証拡張
- 破壊的スクリプトの安全弁強化
- 旧仕様再流入の検出

## 非ゴール

- 外部監視基盤の全面刷新

## 具体タスク

1. `HEAD` / `latest` / `prune:false` を 3区分で定義（禁止 / 条件付き許容 / 例外）
2. `policy-exception-register.md` を運用し、例外の owner と期限を管理
3. `policy-rule-spec.md` を作成し、CI 判定ルールの優先順位を固定
4. pre-ESO `ExternalSecret` 検出ルールを CI に追加
5. Application 所有重複検出ルールを CI に追加
6. 旧仕様再流入検出（`user-applications`, `add-runner`, `arc_repositories` 等）を CI に追加
7. schema 検証（例: kubeconform）導入方針を決定
8. upgrade スクリプトに trap/cleanup 要件を定義
9. destructive script の明示 opt-in ルールを追加
10. restore 観点を含む運用チェックを定義

## 変更対象

- `.github/workflows/`
- `automation/scripts/ci/`
- `automation/scripts/upgrade/`
- `automation/infrastructure/`
- `tasks/policy-exception-register.md`
- `tasks/policy-rule-spec.md`

## 検証

1. 禁止パターンを含む PR が CI fail になること
2. upgrade 中断時でもノード状態が復帰可能であること
3. 例外は台帳登録なしで merge できないこと

## 完了条件

1. CI が主要禁止パターンを検出できる
2. 破壊的操作に安全弁が導入されている
3. 復旧手順の最低要件が明文化されている
4. 運用チェックが定期実行可能な形になっている
5. 旧仕様の再流入を CI が検出できる
