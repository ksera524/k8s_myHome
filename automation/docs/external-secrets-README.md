# External Secrets 運用メモ

## 現行正本

ExternalSecret の正本は GitOps 管理の `manifests/platform/secrets/external-secrets/` です。
`automation/` 配下の旧 Helm 直適用や旧 template 生成の手順は現行運用では使いません。

## 配置ルール

- ESO 本体: `manifests/platform/secrets/external-secrets/operator/`
- SecretStore: `manifests/platform/secrets/external-secrets/stores/`
- ArgoCD 用 Secret: `manifests/platform/secrets/external-secrets/argocd/`
- Harbor 用 Secret: `manifests/platform/secrets/external-secrets/harbor/`
- GitHub Actions / ARC 用 Secret: `manifests/platform/secrets/external-secrets/github-actions/`
- networking 用 Secret: `manifests/platform/secrets/external-secrets/networking/`
- app runtime 用 Secret: `manifests/platform/secrets/external-secrets/app-runtime/`

## 変更手順

1. Secret 本文は Pulumi ESC などの参照元で更新する。
2. Git 側は `manifests/platform/secrets/external-secrets/**` の ExternalSecret 定義だけを変更する。
3. `automation/scripts/ci/validate.sh` を実行する。
4. merge 後は ArgoCD の `config-secrets` Application で同期状態を確認する。

## 確認コマンド

```bash
kubectl get clustersecretstores
kubectl get externalsecrets -A
kubectl get applications -n argocd config-secrets external-secrets-operator
```

## 関連文書

- `docs/manifest-layout.md`
- `docs/environment-contracts.md`
- `tasks/external-secret-split-plan.md`
- `tasks/policy-rule-spec.md`
