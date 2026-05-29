# ポリシー判定仕様（CI向け）

## 目的

- PH5 の CI ルールを機械判定可能な形で定義する
- 「禁止」「条件付き許容」「例外」の優先順位を固定する

## 判定優先順位

1. 例外台帳に登録された対象かを判定
2. 条件付き許容の条件を満たすかを判定
3. 満たさない場合は禁止として fail

## 判定対象ディレクトリ

- `manifests/`
- `automation/`
- `docs/`
- `.github/`
- `Makefile`

`tasks/` は計画文書のため対象外。

## ルール定義

### R-001: legacy app 集約経路の禁止

- パターン: `user-applications|user-application-definitions`
- 期待: 0 件
- 例外可否: 不可

### R-002: runner 自動生成運用の禁止

- パターン: `add-runner\.sh|add-runners-all|arc_repositories`
- 期待: 0 件
- 例外可否: 不可

### R-003: app delivery 経路での直接 rollout 禁止

- パターン: `kubectl rollout restart`
- 対象追加制約: `.github/workflows/` と `automation/scripts/github-actions/` 配下
- 期待: 0 件
- 例外可否: 不可

### R-004: first-party workload の `:latest` 禁止

- パターン: `harbor\.qroksera\.com/.+:latest`
- 期待: 0 件
- 例外可否: 不可

### R-005: pre-ESO `ExternalSecret` 禁止

- 条件: pre-ESO wave/phase で `ExternalSecret` が登場しないこと
- 期待: 0 件
- 例外可否: 不可

### R-006: `HEAD` / `prune:false` の制御

- `HEAD`: bootstrap 直下は条件付き許容、他は例外登録が必要
- `prune:false`: 限定リソースのみ条件付き許容、他は fail

## CI 連携方針

- `automation/scripts/ci/` にルール検出スクリプトを実装
- ルール違反時は対象ファイルとルールIDを出力して fail
- 例外対象は `policy-exception-register.md` を参照して判定

## 例外IDの紐付け仕様

- 例外の判定単位は「対象ファイル + パターン」で行う
- CI 側は少なくとも以下を一致条件として扱う
  - 例外ID
  - 対象（パスまたはファイル名）
  - 関連ルールID（R-00x）
  - 期限
- 期限切れ例外は自動で fail 扱いにする
