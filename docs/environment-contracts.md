# Environment / Access Contract 運用

このドキュメントは current main の非機密 contract と secret 配置の運用ルールです。

## 正本

- 非機密 cluster contract: `manifests/contracts/home-lab/cluster-contract.yaml`
- 非機密 access contract: `manifests/contracts/home-lab/access-surfaces.yaml`
- secret / local 設定: `automation/settings.toml` と Pulumi ESC など ESO 参照元
- `ExternalSecret`: `manifests/platform/secrets/external-secrets/**`

## 変更手順

1. hostname / listener / publish / backend を変える場合は、先に `access-surfaces.yaml` の surface entry を更新する。
2. domain / service IP / NFS / StorageClass を変える場合は、先に `cluster-contract.yaml` を更新する。
3. 対応する `manifests/access/**` または owner-local manifest を更新し、`contracts.k8s-myhome.local/*` annotation を維持する。
4. `tasks/environment-contract-inventory.md` と `tasks/access-surface-matrix.md` の該当行を同期する。
5. `automation/scripts/ci/validate.sh` を実行する。

## 例外

- Helm chart values や raw manifest の値は、PH4 時点では全生成へ寄せず、contract と drift check で追跡する。
- Harbor cleanup CronJob など runtime-local endpoint は access surface にしない。owner-local config として扱う。
- app 固有の非機密値は `apps/<app>/` に残す。複数 workload が共有する場合だけ `platform/shared-config/**` へ昇格する。
- `harbor.qroksera.com` と `192.168.122.100` の registry auth host は、`harbor-external` surface と `network.serviceIPs.gateway` から導出される派生値として扱う。

## Secret 配置

- `ExternalSecret` は domain directory 単位で管理する。
- `platform/argocd-config/**` など pre-ESO path には top-level `ExternalSecret` を置かない。
- 旧外部監視連携の legacy secret は secret 正本に含めない。代替監視基盤は改革後 backlog で別管理する。
