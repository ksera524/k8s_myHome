# PH5: Safety Policy and Validation

## 目的

- 壊れやすい変更を CI/運用ガードで早期検出し、事故を予防する
- runtime / access 分離後の再流入と resource collision を機械検出する

## 背景

- 静的検証中心で、運用整合性や禁止パターンの検出が弱い
- owner 一意性は path 規約だけでは不十分で、render 後の衝突検出が必要

## スコープ

- ポリシー定義
- CI 検証拡張
- CI / ローカル validate toolchain の固定
- 破壊的スクリプトの安全弁強化
- 旧仕様再流入の検出
- access topology / contract / collision の検出

## 検証スタック方針

1. `automation/scripts/ci/validate.sh` を唯一の公開判定入口に固定し、`policy-check.sh` は内部実装として分離する
2. `grep` で足りるルールと manifest-aware でしか判定できないルールを分離し、後者は専用スクリプトで実装する
3. schema 検証は `kubeconform` を採用し、CRD / Helm 生成リソースは allowlist / skip list を伴って段階導入する
4. `warn -> fail` の段階導入が必要な場合でも、期限と owner を `status.md` または例外台帳で追跡する
5. legacy 削除前の current main と、legacy 削除済み target-state branch / cutover candidate commit の required status を区別する

## 非ゴール

- 外部監視基盤の全面刷新

## 具体タスク

1. `HEAD` / `latest` / `prune:false` を 3 区分で定義（禁止 / 条件付き許容 / 例外）し、`latest` は `sandbox` namespace の first-party workload に限定して条件付き許容とする
2. `policy-exception-register.md` を運用し、例外の owner と期限を管理する
3. `policy-rule-spec.md` を作成し、CI 判定ルールの優先順位を固定する
4. pre-ESO `ExternalSecret` 検出ルールを CI に追加する
5. `R-007` として app owner 重複検出ルールを CI に追加する
6. 旧仕様再流入検出（`user-applications`, `add-runner`, `add-runners-bulk`, `arc_repositories` 等）を CI に追加する
7. `apps/**` 配下への access resource 混入検出ルールを CI に追加する
8. rendered resource collision 検出ルールを CI に追加する
9. access surface 契約逸脱（contract 未登録 hostname、publication owner 不一致）検出ルールを CI に追加する
10. Grafana legacy 再流入検出は `policy-rule-spec.md` の canonical Grafana / monitoring legacy identifier set を正として CI に追加し、`grafana` 全面禁止にはしない
11. secret inventory drift 検出として、top-level `ExternalSecret` の許容 path、`policy-rule-spec.md` の canonical fixed-delete credential identifier set、stale template の再流入を CI で検出する。`github-repo-secret` のような live-confirm 対象は fixed delete ではなく inventory 判定へ回す
12. `ExternalSecret` の重複を secret domain 単位で把握できる advisory チェックを追加し、candidate commit では不要 duplicate / legacy Secret を fail-closed にする
13. `latest` 判定は line regex ではなく、raw manifest または render 出力単位で namespace と image を同時評価する
14. schema 検証として `kubeconform` を導入し、CRD allowlist / skip list を定義する
15. `validate.sh` の実行依存（`shellcheck`, `yamllint`, `kustomize` 等）を `flake.nix` / `flake.lock` で pin する
16. `.github/workflows/ci-deploy-validate.yml` を ad-hoc な `apt` / `pip` / 手動 binary install から `nix develop .#default --command automation/scripts/ci/validate.sh` 実行へ移行する
17. ローカル validate の正規実行コマンドを `nix develop .#default --command automation/scripts/ci/validate.sh` に固定する
18. upgrade スクリプトに trap / cleanup 要件を定義する
19. destructive script の明示 opt-in ルールを追加する
20. restore 観点を含む運用チェックを定義する
21. `automation/scripts/ci/policy-check.sh` を実装し、`validate.sh` から呼び出す
22. `R-001` / `R-002` / `R-003` / `R-007` 以降の access / collision ルールの required 化タイミングを「legacy 削除済み candidate commit から」に固定する

## 変更対象

- `.github/workflows/`
- `automation/scripts/ci/`
- `automation/scripts/upgrade/`
- `automation/infrastructure/`
- `flake.nix`
- `flake.lock`
- `tasks/policy-exception-register.md`
- `tasks/policy-rule-spec.md`

## 検証

1. 禁止パターンを含む PR が CI fail になること
2. `sandbox` namespace の first-party workload に限る `:latest` は CI pass し、非 `sandbox` の `:latest` は fail になること
3. `apps/**` に access resource を置く PR が CI fail になること
4. rendered resource collision を含む PR が CI fail になること
5. contract 未登録 hostname / publication 定義を含む PR が CI fail になること
6. upgrade 中断時でもノード状態が復帰可能であること
7. 例外は台帳登録なしで merge できないこと
8. `kubeconform` が対象 manifest の schema 破綻を fail にできること
9. `validate.sh` 実行だけで policy / schema / consistency の主要検証が走ること
10. CI とローカルが同一 Nix toolchain で `validate.sh` を実行できること
11. target-state branch / candidate commit では legacy 削除ルールが fail-closed で動作すること
12. `policy-rule-spec.md` の canonical Grafana / monitoring legacy identifier set の再流入が `validate.sh` で fail になること
13. target-state branch / candidate commit では canonical fixed-delete credential identifier set / stale secret template / pre-ESO `ExternalSecret` が fail になること
14. duplicate / legacy Secret の inventory drift が `validate.sh` で検出できること

## 完了条件

1. `validate.sh` が主要禁止パターンを検出できる
2. 破壊的操作に安全弁が導入されている
3. 復旧手順の最低要件が明文化されている
4. 運用チェックが定期実行可能な形になっている
5. 旧仕様の再流入を `validate.sh` が検出できる
6. `sandbox latest` の条件付き許容が CI で誤検知なく運用できる
7. schema 検証の対象範囲と skip / allowlist が文書化されている
8. app owner 重複と rendered resource collision を `validate.sh` が検出できる
9. access contract / publication 逸脱を `validate.sh` が検出できる
10. legacy 削除ルールの required 化タイミングが文書化され、PH6 cutover 手順と矛盾しない
11. `policy-rule-spec.md` の canonical Grafana / monitoring legacy identifier set の再流入を `validate.sh` が検出できる
12. `validate.sh` の依存 toolchain がローカル / CI で共通化されている
13. legacy secret identifiers と stale secret templates の再流入を `validate.sh` が検出できる
14. pre-ESO path / duplicate secret drift / legacy credential drift を `validate.sh` が検出できる

## 完了記録

- 完了日: 2026-06-02
- 判定: Gate PH5 passed
- `automation/scripts/ci/policy-check.sh` と manifest-aware 実装 `automation/scripts/ci/policy-check.py` を追加し、`validate.sh` から実行する公開判定入口に統合した
- `policy-check.py` は legacy identifier 再流入、app delivery 直接 rollout、first-party `:latest` 条件、pre-ESO `ExternalSecret`、`HEAD` / `prune:false`、child Application owner 重複、`apps/**` access resource 混入、Harbor legacy split-owner artifact、rendered resource collision を検出する
- monitoring / Grafana legacy は PH6 delete scope の既知 live path を allowlist し、それ以外への再流入を fail する
- rendered collision check は child `Application` の repo-local kustomize path を render し、複数 owner が同一 document identity を出力した場合に fail する
- `kubeconform` を `validate.sh` に追加し、CRD / ArgoCD / ExternalSecret / Gateway API / MetalLB / cert-manager 系は skip list と `-ignore-missing-schemas` で段階導入した
- `flake.nix` に `kubeconform` を追加し、`flake.lock` を生成した
- `.github/workflows/ci-deploy-validate.yml` は `nix develop .#default --command automation/scripts/ci/validate.sh` へ移行済み
- 旧 Grafana deploy script と `automation/platform/.github/workflows/` の generated app workflow を削除した
- 検証コマンド: `nix develop path:/work#default --command automation/scripts/ci/validate.sh`（Dockerized Nix）
- 検証結果: green
- 次フェーズ: PH6 Cutover Docs and Cleanup
