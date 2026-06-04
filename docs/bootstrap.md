# Bootstrap

この文書は current main の初期構築と検証入口をまとめます。実行フローの正は `Makefile` と `automation/scripts/run.sh` です。

## 前提

- ホストは Ubuntu 24.04 LTS を想定します。
- VM は QEMU/KVM + libvirt で作成します。
- `make all` と `make phase1` は `sudo` 前提です。
- 設定値は `automation/settings.toml` に置きます。

## 初期設定

```bash
cp automation/settings.toml.example automation/settings.toml
```

`automation/settings.toml` を環境に合わせて編集します。secret 本文は Pulumi ESC などの参照元に置き、Git に直接置きません。

## 全体構築

```bash
make all
```

`make all` は次の順に実行します。

1. `make phase1`
2. `make phase2`
3. `make bootstrap`
4. `make phase5`

## 個別入口

```bash
make phase1
make phase2
make bootstrap
make phase5
```

`make phase3` は bootstrap 互換入口、`make phase4` は root Application 再適用です。通常は `make bootstrap` を使います。

## GitOps Bootstrap

`make bootstrap` は `automation/scripts/run.sh bootstrap` を経由し、`automation/platform/platform-deploy.sh` を実行します。

root `Application` は次です。

```text
manifests/bootstrap/app-of-apps.yaml
```

## 検証

```bash
make phase5
```

`make phase5` は既定で `k8suser@192.168.122.10` に SSH し、`/etc/kubernetes/admin.conf` をローカル `~/.kube/config` に同期してから検証します。

CI またはライブ検証をスキップしたい場合は次を使います。

```bash
VERIFY_SKIP_SSH=true make phase5
```

## 静的検証

```bash
make validate
nix develop .#default --command automation/scripts/ci/validate.sh
make validate-local
```

`automation/scripts/ci/validate.sh` は shellcheck、yamllint、全 `manifests/**/kustomization.yaml` の `kustomize build`、整合性チェックを実行します。

## ログ

実行ログは次に出力されます。

```text
automation/run.log
```

失敗時は `automation/run.log` と `make phase5` の出力を先に確認します。
