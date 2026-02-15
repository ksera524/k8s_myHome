# マニフェスト配置ルール

このドキュメントは `manifests/` 配下の配置ルールを定義します。GitOps 運用と App-of-Apps 構成の一貫性を保つために、ここで定めたルールに従ってください。

## トップレベルの責務

- `bootstrap/`: ArgoCD の Root/App-of-Apps のみ
- `core/`: Namespace / StorageClass / Cluster-wide 基本設定
- `infrastructure/`: クラスタ基盤（networking / security / storage など）
- `platform/`: GitOps運用基盤・CI/CD・Secrets運用（ArgoCD設定、ESO、ARC等）
- `monitoring/`: 監視関連の manifests/values
- `apps/`: ユーザーアプリの実マニフェスト

## ArgoCD Application 定義

- Root App-of-Apps は `bootstrap/app-of-apps.yaml` に配置
- ユーザーアプリ向け Application 定義は `bootstrap/applications/user-apps/` に配置
- 基盤コンポーネント向け Application は `bootstrap/app-of-apps.yaml` から参照
- `core/` 以下に Application 定義を置かない

## cert-manager 関連

- Issuer/Certificate/SecretStore など cert-manager 由来リソースは `infrastructure/security/cert-manager/` に集約
- Gateway 配下は Gateway/HTTPRoute/TLSPolicy などルーティング系のみ

## ExternalSecrets

- ESO 本体と ExternalSecret 定義は `platform/secrets/external-secrets/` に集約

## monitoring

- 監視関連の manifests/values は `monitoring/` に集約

## Kustomize / App-of-Apps の原則

- 同一リソースが複数経路で apply されないこと
- `manifests/**/kustomization.yaml` は同階層内のみを責務とする
- App-of-Apps は `path:` で kustomize ディレクトリを参照する

## スクリプト適用の原則

- `.sh` で `kubectl apply` するのはブートストラップ最小限のみ
- それ以外は ArgoCD 経由に寄せる
