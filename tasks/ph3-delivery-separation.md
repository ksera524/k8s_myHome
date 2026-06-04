# PH3: Delivery Separation

## 目的

- infra 管理と app delivery を分離し、責務境界を明確化する
- runtime 変更と access 変更の変更経路を整理し、二重管理を防ぐ

## 背景

- infra repo 側で app workflow 生成・再起動まで実行しており、境界が混在
- `apps` workload と `access` 公開面の変更粒度が混ざると review / rollback 単位が曖昧になる

## スコープ

- app deploy フローを GitOps commit 経由へ統一
- first-party workload の image tag ルール整理（`sandbox` namespace のみ `:latest` を条件付き許容）
- runner 権限見直し
- `add-runner` 系自動生成運用の廃止
- runtime / access の変更契約分離

## 新運用契約

1. app repo workflow / release bot が行うのは `image build/push` と `infra repo PR 作成` までとする
2. runtime 変更の正本は `manifests/apps/<app>/` または app 専用 values のみとし、PR は `1 app / 1 image update / 1 PR` に固定する
3. access 変更の正本は `manifests/access/<service>/` と `manifests/contracts/home-lab/access-surfaces.yaml` とし、hostname / route / tunnel / DNS 変更は runtime PR と分けて扱えるようにする
4. merge 条件は「policy / validate / app 固有 CI が green」かつ infra owner review 済みとする
5. 失敗時の再実行は PR の再生成または同一 PR 更新で行い、`kubectl` 直接変更へフォールバックしない
6. runner / bot の credential は repo-scoped とし、cluster 変更権限は持たせない

## 非ゴール

- 各アプリの機能改修

## 具体タスク

1. app repo と infra repo の責務契約を文書化する
2. image 更新方式を確定する（app repo workflow または release bot が infra repo へ `1 app / 1 image update / 1 PR` を作成）
3. `:latest` は `sandbox` namespace の first-party workload に限定し、それ以外は immutable tag/digest に移行するルールを定義する
4. app delivery での `kubectl` 直接変更（特に rollout restart）を禁止する
5. `automation/scripts/github-actions/add-runner.sh` / `add-runners-bulk.sh` を新運用から切り離し、PH6 cutover で削除する差分を準備する
6. `automation/templates/github-actions-workflow.yml` と `arc_repositories` 運用を新運用から切り離し、PH6 cutover で削除する差分を準備する
7. runner 定義を manifests 正本（Git 管理）へ移行する
8. ARC runner / PR bot の credential, RBAC, secret 取り扱いを最小化する
9. `harbor-auth` と `github-auth` を旧 automation 互換 Secret として棚卸しし、`add-runner` 廃止と同じ change set で削除する差分を準備する
10. runner / bot が必要とする credential は `github-multi-repo-secret` 等の repo-scoped Secret に縮約し、`harbor-auth` のような shared push credential 読み出しを新運用から外す
11. `automation/scripts/common-k8s-utils.sh` や `automation/templates/external-secrets/**` の legacy secret 名依存を PH6 cutover 削除対象として固定する
12. Harbor の sandbox image cleanup/retention を `sandbox latest` 条件付き許容と整合させ、`harbor-access` ではなく Harbor runtime ops の責務として固定する
13. 新規アプリ onboarding 手順を `runtime + access` の 2 面で更新する
14. runtime 変更 PR と access 変更 PR の切り分け基準を examples 付きで定義する

## 変更対象

- `automation/scripts/github-actions/`
- `automation/scripts/common-k8s-utils.sh`
- `automation/templates/github-actions-workflow.yml`
- `automation/templates/external-secrets/`
- `automation/settings.toml*`
- `automation/platform/platform-deploy.sh`
- `Makefile`
- `manifests/platform/ci-cd/github-actions/`
- `manifests/apps/`
- `manifests/access/`
- `manifests/contracts/home-lab/access-surfaces.yaml`
- `docs/app-delivery.md`
- `docs/bootstrap.md`
- `docs/operations.md`
- `docs/access.md`

## 検証

1. app deploy が GitOps 経由で完結すること
2. runner が不要なクラスタ変更権限を持たないこと
3. `add-runner` / `add-runners-bulk` / `add-runners-all` / `arc_repositories` が新運用から切り離され、PH6 cutover 用の削除差分が準備済みであること
4. `sandbox` namespace の first-party workload は `:latest` で pass し、非 `sandbox` は fail になること
5. runtime 変更と access 変更の変更経路が docs と policy に反映されていること
6. runner / bot が `github-auth` / `harbor-auth` のような legacy shared credential に依存しないこと
7. legacy secret / RBAC / template の削除差分が `add-runner` 廃止と同じ PH6 入力に束ねられていること
8. manifests 正本の runner credential が repo-scoped に縮約されていること

## 完了条件

1. infra repo が app 固有 workflow 生成に依存しない
2. app release は commit/PR ベースで追跡可能
3. first-party workload の `:latest` は `sandbox` namespace に限定されている
4. onboarding 手順が新モデルに一致している
5. app delivery 経路に cluster 直接変更が残っていない
6. Harbor の sandbox image cleanup/retention が `sandbox latest` 条件付き許容と矛盾せず、runtime owner 側の運用責務として定義されている
7. runtime 変更と access 変更の切り分け基準が明文化されている
8. runner / bot credential が repo-scoped に縮約されている
9. `harbor-auth` / `github-auth` など legacy automation Secret の削除差分が PH6 入力として固定されている

## 完了記録

- 完了日: 2026-06-02
- 判定: Gate PH3 passed
- `Makefile` から `add-runner` / `add-runners-all` ターゲットを削除し、infra repo 側の app workflow / runner 自動生成入口を除去した
- `automation/scripts/github-actions/` の runner 生成スクリプト、生成済み workflow、`setup-arc.sh`、`automation/templates/github-actions-workflow.yml`、legacy secret template、`common-k8s-utils.sh` を削除した
- `manifests/platform/ci-cd/github-actions/runners-appset.yaml` を runner 定義の Git 正本とし、`github-actions-rbac.yaml` は ServiceAccount のみへ縮小した
- Runner ServiceAccount から shared Secret 読み取り権限と sandbox Deployment patch 権限を削除し、app delivery の cluster 直接変更経路を断った
- `docs/app-delivery.md`, `docs/operations.md`, `docs/bootstrap.md`, `docs/gitops.md`, `AGENTS.md`, `automation/settings.toml.example` を GitOps PR ベースの app delivery 契約へ更新した
- `sandbox` namespace の first-party workload だけが `harbor.qroksera.com/sandbox/*:latest` を使う現状を維持し、非 sandbox の first-party `:latest` は存在しないことを確認した
- `automation/settings.toml` は Git 管理外のローカル設定のため編集対象外。旧 runner 設定が残っていても正本ではなく、runner 定義は `runners-appset.yaml` を正とする
- PH5 では `policy-check.sh` / manifest-aware check / rendered collision check / Nix toolchain pinning を実装する
