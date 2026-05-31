# 構造改革ステータス

最終更新日: 2026-05-31

## Current Phase

- PH2 residual: GitOps topology planning / automation synchronization

## Summary

- PH0 の target operating model、planning artifact、主要設計判断は確定済み
- single root `Application`、child `Application` split、`access/**` owner 層、`sandbox-config` の platform 移設は current repo の事実として扱う
- PH2 は topology 新設ではなく、planning artifact / audit / inventory / stale reference の残差収束を担当する
- `docs/` は current-state、`tasks/` は target-state planning を正とする。ただし main に既に入った topology change は planning 側でも current-state fact として反映する

## In Progress

- PH2 residual: `component-ownership-matrix.md`, `access-surface-matrix.md`, `environment-contract-inventory.md`, `legacy-removal-inventory.md` の current repo 同期
- PH2 residual: `.github/workflows/weekly-version-audit.yml` の monitoring 特別扱い / stale hardcode 追従の整理
- PH2 residual: dead path / stale reference / cutover inventory の整理と PH5 handoff の明文化

## Blocked

- なし

## Next Gate

- Gate PH2: planning artifact が current repo を正しく反映し、legacy monitoring を PH6 delete scope として切り分け、audit / inventory / stale reference の残差が収束していること

## Open Decisions

- なし

## Recently Closed

- PH0/PH2 の未決論点はすべて解消済み
- `sandbox-config` の shared config owner、internal surface ID、service IP 命名、Harbor split owner、access extraction 順は固定済み
- root `Application` の entrypoint と child `Application` discovery source は `manifests/bootstrap/applications/**` に固定済み
- 履歴は `open-issues.md` を参照する

## Notes

- main ブランチに旧新併存を残さない
- `apps/` は workload-only、公開/接続系は `access/` に分離する
- 各サービスは `runtime + access` の pair を持てるが、それ以外の owner 分割は禁止する
- owner 一意性の最終担保は rendered resource collision check とする
- PH5 / PH6 の公式 pass/fail 判定は `automation/scripts/ci/validate.sh` を正とする
- canonical regex / identifier set / validation semantics は `policy-rule-spec.md` を正とする
- `make bootstrap` / `automation/scripts/run.sh bootstrap` / `nix develop .#bootstrap` は PH1 実装後の target-state 名称であり、現行 repo の即時実行手順ではない
- Grafana Cloud と現行 `monitoring` stack は PH6 で完全削除する legacy として扱い、代替監視基盤は `tasks/backlog.md` で別管理する
- Git は空ディレクトリを追跡しないため、PH2 / PH5 の判定対象は workspace-local empty dir ではなく、tracked path / stale reference / 再流入防止ルールとする
