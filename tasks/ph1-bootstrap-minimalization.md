# PH1: Bootstrap Minimalization

## 目的

- 初回 bootstrap の失敗要因を除去し、再構築可能性を高める
- PH2 / PH4 で確定した topology / contract に bootstrap を追従させる
- bootstrap と steady-state の境界を明確化し、bootstrap 入口を最小責務に固定する

## 背景

- bootstrap と steady-state の責務が混在し、依存順不整合が発生しやすい
- topology 確定前に bootstrap を最適化すると手戻りが増える

## スコープ

- ArgoCD 初期導入に必要な最小リソース定義
- ESO 依存リソースの後段移動
- bootstrap 手順の分離
- pre-ESO 適用可能リソースと post-ESO リソースの明確分離
- bootstrap 経路に残る Grafana Cloud / monitoring 自動導線の除去
- bootstrap から access plane の個別収束ロジックを排除
- fresh PC bootstrap 用ローカル toolchain の再現性確保（support lane）

## 非ゴール

- app delivery 方式の変更
- `apps` / `access` の taxonomy 再設計

## 具体タスク

1. bootstrap 対象リソースを「ArgoCD 初期導入 + root Application 適用 + pre-ESO 最小前提」として再定義する
2. pre-ESO で適用される `ExternalSecret` を禁止し、post-ESO へ移動する
3. `manifests/platform/argocd-config/` の pre-ESO 依存（例: registry ExternalSecret）を分離する
4. `manifests/platform/argocd-config/harbor-unified-registry-secrets.yaml` を post-ESO path へ移し、`manifests/platform/argocd-config/**` 配下の top-level `ExternalSecret` を 0 件にする
5. `harbor-registry` の namespace 複製は consumer 実在が確認できる namespace のみに絞り、bootstrap の pre-ESO 必須前提を持たせない
6. `automation/platform/platform-deploy.sh` の steady-state 処理（patch / restart / sync 強制）を切り出す
7. bootstrap 経路から Grafana k8s-monitoring 自動デプロイ導線と `deploy-grafana-*` スクリプト群を除去する
8. bootstrap 経路から access plane の個別収束ロジックを外し、child owner 判断を持たせない
9. `automation/scripts/app-deploy.sh` の責務を bootstrap 境界に合わせて整理し、phase4 の意味と乖離する場合は bootstrap 専用名への改称も含めて検討する
10. bootstrap と steady-state のディレクトリ境界を定義する
11. 初回構築向け smoke test 項目を定義する
12. `flake.nix` / `flake.lock` を追加し、fresh host で使う `devShells.bootstrap` と validate 用 `devShells.default` を定義する
13. Linux 前提のため、ローカル toolchain shell 名は `bootstrap`、wrapper を置く場合も `bootstrap.sh` に固定する
14. `automation/host-setup/setup-host.sh` を Nix-aware にし、`K8S_MYHOME_USE_NIX_TOOLCHAIN=true` の場合は Terraform / Ansible / kubectl / Helm / 汎用 CLI の重複 install を skip しつつ、libvirt / KVM / Docker / systemd は host 側で維持する
15. `README.md` / `docs/quickstart.md` / `docs/setup-guide.md` を `nix develop .#bootstrap` 前提の fresh cluster 導線へ更新し、`make bootstrap` との役割差分を明記する
16. `app-deploy.sh` の責務変更に合わせて `automation/scripts/run.sh` と `Makefile` の phase mapping を同時更新する
17. 公式 bootstrap 入口は既存 `phase3` を流用せず、新設 alias `make bootstrap`（実体: `automation/scripts/run.sh bootstrap`、PH1 完了までは未実装）として固定する
18. `make bootstrap` は GitOps bootstrap 専用入口とし、fresh cluster と PH6 cutover での前提差分（前者は `phase1`/`phase2` 後かつ `phase5` で検証、後者は既存 cluster 前提で `make bootstrap` 実行後に cutover 検証）を明文化する
19. bootstrap 完了条件から現行 `monitoring` stack を外し、初回 bootstrap が Grafana Cloud / `monitoring` namespace 非依存で完了する前提に揃える

## 変更対象

- `manifests/bootstrap/`
- `manifests/platform/argocd-config/`
- `manifests/platform/secrets/`
- `automation/platform/`
- `automation/host-setup/setup-host.sh`
- `automation/scripts/setup-eso-prerequisites.sh`
- `automation/scripts/app-deploy.sh`
- `automation/scripts/run.sh`
- `Makefile`
- `flake.nix`
- `flake.lock`
- `README.md`
- `docs/quickstart.md`
- `docs/setup-guide.md`

## 検証

1. fresh cluster で bootstrap 手順を 2 回再実行し、どちらも手動介入なしで完了すること
2. ESO 未導入時点で ExternalSecret 依存エラーを発生させないこと
3. bootstrap 実行後に「手動 patch / restart なし」で PH3 へ進めること
4. 検証ログ（`automation/run.log` または同等ログ）に重大エラーが残っていないこと
5. fresh cluster 向け実行順序 `make phase1 -> make phase2 -> make bootstrap -> make phase5` が手順として矛盾なく定義されていること
6. bootstrap 実行が Grafana Cloud / Grafana k8s-monitoring の自動デプロイに依存しないこと
7. bootstrap が access plane の個別収束ロジックや child owner 判断を持たないこと
8. fresh Ubuntu host で `nix develop .#bootstrap` から標準手順へ進めること
9. Nix shell 内で phase1 が CLI 重複導入を避けつつ host provisioning を継続できること
10. `manifests/platform/argocd-config/**` に top-level `ExternalSecret` が 0 件であること
11. bootstrap 完了に不要な registry / repository credential が pre-ESO scope に残っていないこと

## 完了条件

1. bootstrap と steady-state の責務が分離されている
2. pre-ESO で `ExternalSecret` が適用されない
3. 初回構築の主要手順がドキュメント化されている
4. smoke test 観点が定義済み
5. bootstrap 入口の責務が ArgoCD root 適用までに限定されている
6. 公式 bootstrap 入口が `make bootstrap`（実体: `automation/scripts/run.sh bootstrap`）に固定されている
7. fresh cluster 用と PH6 cutover 用で `make bootstrap` の前提条件が文書化されている
8. bootstrap 経路に Grafana Cloud / 現行 monitoring stack の自動導線が残っていない
9. bootstrap が access plane の個別制御や owner 判断を持っていない
10. 新規 PC 向けローカル toolchain が `nix develop .#bootstrap` で再現できる
11. `nix develop .#bootstrap` と `make bootstrap` の役割差分が文書化されている
12. `manifests/platform/argocd-config/**` の top-level `ExternalSecret` が 0 件である
13. bootstrap 完了に不要な registry / repository credential が post-ESO path へ分離済みである
