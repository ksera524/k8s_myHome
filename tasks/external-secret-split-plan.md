# ExternalSecret Split Plan

## 目的

- `manifests/platform/secrets/external-secrets/` を secret domain 単位に分割し、`external-secret-resources.yaml` の monolith を解消する
- pre-ESO 配置、legacy credential、stale template、未使用候補を分離し、PH1 / PH3 / PH4 / PH6 の実施順に接続する
- first cut では consumer 側の `secretName` / `target.name` を極力変えず、file split と削除判定を先に進める

## 前提

- top-level `ExternalSecret` は target-state でも `manifests/platform/secrets/external-secrets/**` 配下だけに置く
- secret 値本文は引き続き Git に置かず、`automation/settings.toml` と ESO の参照元を正本とする
- app / chart / script 側 consumer が既に安定しているものは、first cut で Secret schema を変えない
- `ghcr-nginx-charts-secret`、`github-repo-secret`、`harbor-registry` の `default` / `argocd` copy は repo 参照だけで未使用断定しない
- keep / delete / live-confirm の判定正本は本ファイルとし、`legacy-removal-inventory.md` と `ph6-cutover-docs-and-cleanup.md` は本ファイルを参照する索引として扱う

## target tree

```text
manifests/platform/secrets/external-secrets/
  kustomization.yaml
  stores/
    kustomization.yaml
    pulumi-esc-secretstore.yaml
  argocd/
    kustomization.yaml
    argocd-github-oauth-secret.yaml
  harbor/
    kustomization.yaml
    harbor-admin-secret.yaml
    harbor-registry-sandbox.yaml
  github-actions/
    kustomization.yaml
    github-multi-repo-secret.yaml
  networking/
    kustomization.yaml
    cloudflared-secret.yaml
    cloudflare-api-token.yaml
    tailscale-oauth.yaml
  app-runtime/
    kustomization.yaml
    slack-secret.yaml
    rustfs-auth-rustfs.yaml
    rustfs-auth-sandbox.yaml
```

補足:

- `argocd/repositories/` は first cut では作らない
- `legacy-monitoring/` は作らず、Grafana 系は PH6 cutover で削除する
- live-confirm の結果 keep が必要と判明した場合のみ `argocd/repositories/ghcr-nginx-charts-secret.yaml` などを追加する

## current-to-target mapping

| Current Location | Current Name | Target Path | Action | Notes |
|---|---|---|---|---|
| `pulumi-esc-secretstore.yaml` | `pulumi-esc-store` | `stores/pulumi-esc-secretstore.yaml` | keep | ClusterSecretStore は最上流。分割後も root `kustomization.yaml` の先頭で読む |
| `argocd-github-oauth-secret.yaml` | `argocd-github-oauth-secret` | `argocd/argocd-github-oauth-secret.yaml` | keep | `argocd-secret` へ merge する現行仕様を維持 |
| `external-secret-resources.yaml` | `harbor-admin-secret` | `harbor/harbor-admin-secret.yaml` | keep | Harbor chart と cleanup CronJob の consumer がある |
| `external-secret-resources.yaml` | `cloudflared-secret` | `networking/cloudflared-secret.yaml` | keep | `manifests/access/cloudflared/manifest.yaml` が consumer |
| `external-secret-resources.yaml` | `cloudflare-api-token` | `networking/cloudflare-api-token.yaml` | keep | cert-manager issuer の consumer がある |
| `external-secret-resources.yaml` | `tailscale-oauth` | `networking/tailscale-oauth.yaml` | keep | chart 既定 Secret 名利用の可能性が高く、削除しない |
| `external-secret-resources.yaml` | `github-multi-repo-secret` | `github-actions/github-multi-repo-secret.yaml` | keep | ARC runner の現行 consumer がある |
| `external-secret-resources.yaml` | `slack-secret` | `app-runtime/slack-secret.yaml` | keep | `SLACK_BOT_TOKEN` consumer がある。`token` alias は second cut で削減候補 |
| `external-secret-resources.yaml` | `rustfs-auth` (`rustfs`) | `app-runtime/rustfs-auth-rustfs.yaml` | keep | RustFS chart の `existingSecret` consumer がある |
| `external-secret-resources.yaml` | `rustfs-auth` (`sandbox`) | `app-runtime/rustfs-auth-sandbox.yaml` | keep | `api-hub` / `home-camera` consumer がある |
| `manifests/platform/argocd-config/harbor-unified-registry-secrets.yaml` | `harbor-registry` (`sandbox`) | `harbor/harbor-registry-sandbox.yaml` | move+keep | pre-ESO path から post-ESO path へ移す。target secret 名は維持 |
| `external-secret-resources.yaml` | `harbor-auth-secret` | - | delete | 旧 automation 互換。PH3 runner / bot credential 縮約と同時に削除 |
| `external-secret-resources.yaml` | `github-auth-secret` | - | delete | 旧 automation 互換。`github-multi-repo-secret` へ責務集約 |
| `external-secret-resources.yaml` | `harbor-registry-secret` | - | delete | repo 内 consumer 未確認。`harbor-auth` とも責務重複 |
| `grafana-cloud-external-secret.yaml` | `grafana-cloud-credentials` | - | delete | PH6 monitoring legacy 削除対象 |
| `grafana-monitoring-external-secret.yaml` | `grafana-cloud-monitoring` | - | delete | PH6 monitoring legacy 削除対象 |
| `manifests/platform/argocd-config/harbor-unified-registry-secrets.yaml` | `harbor-registry` (`default`) | - | live-confirm | repo 参照未確認。keep が必要なら `harbor/harbor-registry-default.yaml` として再配置 |
| `manifests/platform/argocd-config/harbor-unified-registry-secrets.yaml` | `harbor-registry` (`argocd`) | - | live-confirm | repo 参照未確認。keep が必要なら `harbor/harbor-registry-argocd.yaml` として再配置 |
| `external-secret-resources.yaml` | `ghcr-nginx-charts-secret` | - | live-confirm | current wave 上は不要の可能性が高い。ArgoCD repo inventory を確認して keep/delete を判定 |
| `external-secret-resources.yaml` | `github-repo-secret` | - | live-confirm | Image Updater consumer 未確認。keep が必要な場合のみ `argocd/repositories/` を追加 |

## kustomization split 方針

### root `kustomization.yaml`

- `resources:` は child directory の `kustomization.yaml` だけを列挙する
- 並び順は `stores -> argocd -> harbor -> github-actions -> networking -> app-runtime` とする
- `legacy-monitoring` は resources に含めない

### child `kustomization.yaml`

- 1 domain 1 directory 1 kustomization とし、domain 内でも `ExternalSecret` は原則 1 file 1 resource に分割する
- same domain 内でだけ review できる粒度にし、domain 間の accidental coupling を避ける

## first cut / second cut

### first cut

- file split のみを行い、既存 `target.name` と template data shape は変えない
- `harbor-unified-registry-secrets.yaml` の `sandbox` 分だけを移設し、pre-ESO path の top-level `ExternalSecret` を解消する
- Grafana 系 2 file を削除対象として固定する

### second cut

- `slack-secret` の `token` alias の削除可否を app consumer ベースで再評価する
- Harbor credential の dual format (`username/password`, env vars, dockerconfigjson) を consumer 単位で削減する
- RustFS の 2 namespace 複製を維持するか、shared source + copy 方式にするかを再評価する

## live-confirm 手順

1. ArgoCD repository 一覧で `ghcr-nginx-charts` と `github-k8s-myhome` の consumer 実在を確認する
2. live cluster の `default` / `argocd` namespace に `harbor-registry` が mount / `imagePullSecrets` / manual pull 用に使われていないか確認する
3. keep が必要なら target owner と exit condition を `legacy-removal-inventory.md` または cutover 記録に残す
4. keep 根拠が無ければ PH6 cutover candidate commit で削除する

## implementation order

1. `external-secret-resources.yaml` から keep 対象を file-per-secret へ分割する
2. `kustomization.yaml` を child directory 参照へ変える
3. `harbor-unified-registry-secrets.yaml` の `sandbox` 分を `harbor/` へ移し、`argocd-config` 配下を空にする
4. Grafana 系 file を resources から外し、PH6 削除対象に固定する
5. `harbor-auth` / `github-auth` を使う automation / RBAC / template を PH3 変更差分へ寄せる
6. live-confirm 対象を確認後、不要分を cutover candidate commit から削除する

## merge gate

- `manifests/platform/argocd-config/**` に top-level `ExternalSecret` が 0 件
- `manifests/platform/secrets/external-secrets/**` の `ExternalSecret` が file-per-secret で review 可能
- Grafana legacy secret が root `kustomization.yaml` から外れている
- `harbor-auth` / `github-auth` の削除計画が PH3 / PH6 と整合している
- live-confirm 対象の keep / delete 根拠が tasks 側に残っている
