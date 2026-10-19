# Secrets

この文書は External Secrets Operator と Secret 配置の current-state ルールです。

## 正本

- ESO 本体: `manifests/platform/secrets/external-secrets/operator/`
- SecretStore: `manifests/platform/secrets/external-secrets/stores/`
- ExternalSecret: `manifests/platform/secrets/external-secrets/**`
- secret 本文: Pulumi ESC などの外部参照元
- local 設定: `automation/settings.toml`

## 配置

| Domain | Path |
|---|---|
| stores | `manifests/platform/secrets/external-secrets/stores/` |
| ArgoCD | `manifests/platform/secrets/external-secrets/argocd/` |
| Harbor | `manifests/platform/secrets/external-secrets/harbor/` |
| GitHub Actions / ARC | `manifests/platform/secrets/external-secrets/github-actions/` |
| networking | `manifests/platform/secrets/external-secrets/networking/` |
| observability | `manifests/platform/secrets/external-secrets/observability/` |
| app runtime | `manifests/platform/secrets/external-secrets/app-runtime/` |

`platform/argocd-config/**` など pre-ESO path に top-level `ExternalSecret` を置きません。

## 同期フロー

```text
Pulumi ESC -> ClusterSecretStore -> ExternalSecret -> Kubernetes Secret
```

ClusterSecretStore は `pulumi-esc-store` です。

## 変更手順

1. Secret 本文は Pulumi ESC などの参照元で更新します。
2. Git 側は `manifests/platform/secrets/external-secrets/**` の ExternalSecret 定義だけを変更します。
3. `automation/scripts/ci/validate.sh` を実行します。
4. merge 後は ArgoCD の `config-secrets` Application で同期状態を確認します。

## 確認コマンド

```bash
kubectl get clustersecretstores
kubectl describe clustersecretstore pulumi-esc-store
kubectl get externalsecrets -A
kubectl describe externalsecret <name> -n <namespace>
kubectl get applications -n argocd config-secrets external-secrets-operator
```

## 強制同期

必要な場合のみ ExternalSecret に annotation を付けて再同期します。

```bash
kubectl annotate externalsecret <name> -n <namespace> \
  force-sync="$(date +%s)" --overwrite
```

## Harbor 内部認証情報

`harbor/harbor-internal-secret` は `config-secrets` の ExternalSecret が管理します。
Harbor chart のランダム生成を避けるため、現行 Secret の値を ESC の次の secret 値へ移行しています。

| ESC キー（`harbor` 配下） | Secret キー |
|---|---|
| `core_secret` | `secret` |
| `encryption_key` | `secretKey` |
| `token_cert` / `token_key` | `tls.crt` / `tls.key` |
| `xsrf_key` | `CSRF_KEY` |
| `jobservice_secret` | `JOBSERVICE_SECRET` |
| `registry_secret` | `REGISTRY_HTTP_SECRET` |
| `registry_password` / `registry_htpasswd` | `REGISTRY_PASSWD` / `REGISTRY_HTPASSWD` |

Harbor を同期する前に ExternalSecret の Ready を確認します。
これらは関連する値をセットで管理し、特に暗号化キーを不用意に変更しないでください。
token 証明書は自動再生成されなくなるため、有効期限を管理し、更新時は対応する秘密鍵も ESC へ登録します。
変更した内部認証情報をプロセスへ反映する際は core / registry / jobservice の計画的な再起動が必要です。

Harbor 本体の管理・内部認証用 ESC 値は `harbor.*` に統一します。`harbor.admin_password` は管理者パスワードで、
管理者 Secret、各 namespace の image pull Secret、ARC の認証 Secret が共通で参照します。
旧スカラー `harbor` とトップレベルの `harbor-internal-*` は使用しません。
各 leaf は暗号化した secret 値のまま保持し、Kubernetes Secret の名前・キー・値は変更しません。

## 共通 PostgreSQL

パスワードは ESC の `postgresql.admin_password` と `postgresql.password` を正本とする。
`config-secrets` が `database/postgresql-input`、`harbor/harbor-database-secret`、
`observability/grafana-postgresql` に配布する。
入力 Secret は PGO の生成 Secret と分離し、2 分ごとの資格情報 Job が変更時だけ PGO に反映する。
Harbor と他アプリは共用ロール `app`・共通パスワードを使用し、TLS 検証を行う。運用・復旧は [共通 PostgreSQL](shared-postgresql.md) を参照。
この environment の `fn::secret` は追加後 22 個。DB 用は管理用・アプリ共用の 2 個で、
同じ値を複数 Namespace に配布するための重複登録は行わない。
