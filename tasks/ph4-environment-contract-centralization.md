# PH4: Environment Contract Centralization

## 目的

- 環境固有値（IP/DNS/StorageClass 等）の正本を一元化し、ドリフトを抑止する
- 非機密 contract と secret/local 設定を分離し、変更経路を明確化する

## 背景

- 固定値が `automation/` と `manifests/` に分散し、変更時の漏れが起きやすい

## スコープ

- 環境契約ファイルの定義
- 値の棚卸しと移行計画
- 参照ルール統一
- 生成/反映/検証の運用方式定義

## 非ゴール

- マルチ環境同時対応

## 具体タスク

1. 環境固有値の棚卸し（IP, DNS, domain, storage, endpoints）
2. 非機密 contract 正本の配置を決定（例: `manifests/contracts/home-lab/`）
3. secret/local 設定の正本を `automation/settings.toml` に限定
4. `manifests/` 側の参照方式を定義（values/patch/replacements で反映）
5. `app-of-apps.yaml` 内 inline values をファイル参照へ分解
6. CoreDNS/Harbor/Gateway/Tailscale/NFS の移行優先順位を決定
7. 置換漏れ検出用チェックリストを作成
8. 例外的に固定値を許容する条件を明文化

## 変更対象

- `automation/settings.toml*`
- `automation/scripts/settings-loader.sh`
- `manifests/infrastructure/`
- `manifests/platform/`
- `manifests/apps/`
- `manifests/bootstrap/app-of-apps.yaml`
- `manifests/contracts/`
- `docs/kubernetes-architecture.md`
- `docs/manifest-layout.md`

## 検証

1. 主要環境値が 1 か所から追跡できること
2. 置換漏れ検出チェックで差分が把握できること
3. 非機密 contract と secret/local 設定が混在していないこと

## 完了条件

1. 環境契約の正本が定義済み
2. 主要コンポーネントが正本ベースに移行済み
3. ハードコード許容例外が文書化済み
4. 値変更時の作業手順が明記されている
5. `settings.toml` は secret/local 設定の責務に限定されている
