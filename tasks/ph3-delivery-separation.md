# PH3: Delivery Separation

## 目的

- infra 管理と app delivery を分離し、責務境界を明確化する

## 背景

- infra repo 側で app workflow 生成・再起動まで実行しており、境界が混在

## スコープ

- app deploy フローを GitOps commit 経由へ統一
- `latest` 依存の廃止（first-party workloads）
- runner 権限見直し
- `add-runner` 系自動生成運用の廃止

## 非ゴール

- 各アプリの機能改修

## 具体タスク

1. app repo と infra repo の責務契約を文書化
2. image 更新方式を確定（infra repo への PR bot 方式）
3. `latest` を immutable tag/digest に移行するルール定義
4. app delivery での `kubectl` 直接変更（特に rollout restart）を禁止
5. `automation/scripts/github-actions/add-runner.sh` / `add-runners-bulk.sh` を削除
6. `automation/templates/github-actions-workflow.yml` と `arc_repositories` 運用を削除
7. runner 定義を manifests 正本（Git 管理）へ移行
8. ARC runner の RBAC 最小化と secret 取り扱いを見直し
9. 新規アプリ onboarding 手順を更新

## 変更対象

- `automation/scripts/github-actions/`
- `automation/templates/github-actions-workflow.yml`
- `automation/settings.toml*`
- `automation/platform/platform-deploy.sh`
- `Makefile`
- `manifests/platform/ci-cd/github-actions/`
- `manifests/apps/`
- `docs/applications.md`
- `docs/setup-guide.md`
- `docs/operations-guide.md`
- `docs/quickstart.md`

## 検証

1. app deploy が GitOps 経由で完結すること
2. runner が不要なクラスタ変更権限を持たないこと
3. `add-runner` / `add-runners-all` / `arc_repositories` 参照が repo から消えていること

## 完了条件

1. infra repo が app 固有 workflow 生成に依存しない
2. app release は commit/PR ベースで追跡可能
3. `latest` 運用が原則廃止されている
4. onboarding 手順が新モデルに一致している
5. app delivery 経路に cluster 直接変更が残っていない
