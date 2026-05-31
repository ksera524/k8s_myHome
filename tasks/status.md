# 構造改革ステータス

最終更新日: 2026-05-31

## Current Phase

- PH2: GitOps Topology Normalization and Access Extraction

## Summary

- PH0 の target operating model、planning artifact、主要設計判断は確定済み
- active 正本は `roadmap.md`, `status.md`, 各 PH 文書, `policy-rule-spec.md`, `cutover-checklist.md`, `legacy-removal-inventory.md` とする
- `open-issues.md` は解消済み論点の履歴アーカイブとして保持し、active な未決論点は本書の `Open Decisions` だけで管理する
- `docs/` は current-state、`tasks/` は target-state planning を正とする

## In Progress

- PH2 実装: root / child Application の file split 差分を準備
- PH2 実装: `access/**` target path と shared access plane owner を作成
- 文書整備: planning 正本と implementation 正本の境界を再編

## Blocked

- なし

## Next Gate

- Gate PH2: target topology 実装完了、旧 owner 参照更新、dead path / hardcode 追従の完了

## Open Decisions

- なし

## Recently Closed

- PH0/PH2 の未決論点はすべて解消済み
- `sandbox-config` の shared config owner、internal surface ID、service IP 命名、Harbor split owner、access extraction 順、dead path 削除方針は固定済み
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
