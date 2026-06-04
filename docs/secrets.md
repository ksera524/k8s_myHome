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
