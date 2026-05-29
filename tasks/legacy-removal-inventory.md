# 旧仕様削除インベントリ

## 目的

- PH6 cutover で main から削除すべき旧仕様を一覧化する
- 削除漏れを防ぎ、完了判定を明確化する

## 削除対象（確定）

### 1) `user-applications` 系

- `manifests/bootstrap/app-of-apps.yaml` 内の `user-applications`
- `manifests/bootstrap/app-of-apps.yaml` 内の `user-application-definitions`
- `automation/platform/platform-deploy.sh` の `user-applications` 参照
- `automation/scripts/verify.sh` の `user-applications` 参照
- `docs/setup-guide.md` の `user-applications` 同期手順
- `docs/gitops-design.md` の `user-applications` 前提記述

### 2) `add-runner` 自動生成系

- `automation/scripts/github-actions/add-runner.sh`
- `automation/scripts/github-actions/add-runners-bulk.sh`
- `automation/templates/github-actions-workflow.yml`
- `Makefile` の `add-runner` / `add-runners-all` ターゲット
- `automation/settings.toml*` の `arc_repositories` 運用
- `docs/operations-guide.md` / `docs/setup-guide.md` / `docs/quickstart.md` の該当手順

### 3) 旧 app delivery 経路

- app delivery workflow からの `kubectl` 直接操作
- app delivery workflow からの `kubectl rollout restart` 依存
- first-party workloads の `:latest` 運用

## 検証コマンド（PH6）

```bash
grep -R -n -E 'user-applications|user-application-definitions' manifests automation docs .github Makefile
grep -R -n -E 'add-runner\.sh|add-runners-bulk\.sh|add-runners-all|arc_repositories' manifests automation docs .github Makefile
grep -R -n -E 'kubectl rollout restart' automation docs .github manifests
```

上記は最終的に 0 件を目標とする（`tasks/` は計画文書のため対象外）。
