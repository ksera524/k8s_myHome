# Manifests

この文書は current main の `manifests/` 配置規約です。

## トップレベル

| Path | 責務 |
|---|---|
| `bootstrap/` | ArgoCD root/child `Application` |
| `core/` | Namespace / StorageClass / cluster-wide 基本設定 |
| `infrastructure/` | networking / security / storage などクラスタ基盤 |
| `platform/` | GitOps 運用基盤、CI/CD、Secrets、shared config、repo-local wrapper |
| `access/` | Gateway / DNS / Cloudflared / HTTPRoute |
| `contracts/` | 非機密 environment / access contract |
| `apps/` | ユーザーアプリ workload-only manifest |

## ArgoCD Application

- root `Application` は `bootstrap/app-of-apps.yaml` に 1 件だけ置きます。
- child `Application` は `bootstrap/applications/` 配下に `1 Application / 1 file` で置きます。
- child `Application` は `core`, `infrastructure`, `platform`, `access`, `user-apps` に分類します。
- `core/` 以下に `Application` 定義を置きません。

## Runtime / Access

- `apps/` は Deployment / Service / CronJob など workload 本体だけを持ちます。
- `HTTPRoute` / `Gateway` / `Cloudflared` / DNS publish は `access/` に置きます。
- remote chart を含む owner は `platform/<component>/` の repo-local wrapper を正本にします。
- 複数 workload が共有する非機密設定は `platform/shared-config/` に置きます。

## cert-manager

- Issuer / Certificate / SecretStore など cert-manager 系リソースは `infrastructure/security/cert-manager/` に集約します。
- Gateway 配下は Gateway / HTTPRoute / TLSPolicy など routing 系だけを置きます。

## ExternalSecret

- ESO 本体と `ExternalSecret` 定義は `platform/secrets/external-secrets/` に集約します。
- domain directory は `stores/`, `argocd/`, `harbor/`, `github-actions/`, `networking/`, `app-runtime/` です。
- `platform/argocd-config/**` など pre-ESO path に top-level `ExternalSecret` を置きません。

## Contracts

- 非機密 cluster contract: `manifests/contracts/home-lab/cluster-contract.yaml`
- 非機密 access contract: `manifests/contracts/home-lab/access-surfaces.yaml`
- secret / local 設定: `automation/settings.toml` と Pulumi ESC など ESO 参照元

hostname / listener / backend / publish を変更する場合は `access-surfaces.yaml` を先に更新します。domain / service IP / NFS / StorageClass を変更する場合は `cluster-contract.yaml` を先に更新します。

## Kustomize

- 同一リソースを複数経路で apply しません。
- `manifests/**/kustomization.yaml` は同階層内の責務に閉じます。
- root `Application` は `bootstrap/applications/` の top-level `kustomization.yaml` を参照します。
