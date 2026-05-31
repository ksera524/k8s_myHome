# マニフェスト配置ルール

このドキュメントは current main の `manifests/` 配置ルールを定義します。GitOps 運用と App-of-Apps 構成の一貫性を保つために、ここで定めたルールに従ってください。

## トップレベルの責務

- `bootstrap/`: ArgoCD の root `Application` と child `Application` 定義
- `core/`: Namespace / StorageClass / Cluster-wide 基本設定
- `infrastructure/`: クラスタ基盤（networking / security / storage など）
- `platform/`: GitOps運用基盤・CI/CD・Secrets運用・shared config・repo-local wrapper
- `access/`: Gateway / DNS / Cloudflared / HTTPRoute などの公開/接続系リソース
- `monitoring/`: 監視関連の values / 補助ファイル
- `apps/`: ユーザーアプリの workload-only マニフェスト

## ArgoCD Application 定義

- root `Application` は `bootstrap/app-of-apps.yaml` に 1 件だけ置く
- child `Application` は `bootstrap/applications/` 配下で `1 Application / 1 file` とする
- child `Application` は `bootstrap/applications/{core,infrastructure,platform,access,user-apps}/` に配置する
- `core/` 以下に `Application` 定義を置かない

## runtime / access 分離

- `apps/` には Deployment / Service / CronJob など workload 本体だけを置く
- `HTTPRoute` / `Gateway` / `Cloudflared` / DNS publish は `access/` に置く
- 複数 workload が共有する非機密設定は `platform/shared-config/` に置く
- remote chart を含む owner は `platform/<component>/` の repo-local wrapper を正本にする

## cert-manager 関連

- Issuer / Certificate / SecretStore など cert-manager 由来リソースは `infrastructure/security/cert-manager/` に集約する
- `Gateway` 配下は `Gateway` / `HTTPRoute` / `TLSPolicy` などルーティング系のみを置く

## ExternalSecrets

- ESO 本体と `ExternalSecret` 定義は `platform/secrets/external-secrets/` に集約する

## Kustomize / App-of-Apps の原則

- 同一リソースが複数経路で apply されないこと
- `manifests/**/kustomization.yaml` は同階層内のみを責務とする
- root `Application` は `bootstrap/applications/` の top-level `kustomization.yaml` を参照する

## スクリプト適用の原則

- `.sh` で `kubectl apply` するのはブートストラップ最小限のみ
- それ以外は ArgoCD 経由に寄せる
