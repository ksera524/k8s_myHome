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

## GitOps Bootstrap

`make bootstrap` は `automation/scripts/run.sh bootstrap` を経由し、`automation/platform/platform-deploy.sh` を実行します。
ArgoCD install manifest と ApplicationSet CRD は `automation/platform/platform-deploy.sh` の `ARGOCD_BOOTSTRAP_VERSION` で同じ tag に固定します。更新時は `make validate` と live cluster の `make phase5` で確認します。

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

`automation/scripts/ci/validate.sh` は shellcheck、yamllint、全 `manifests/**/kustomization.yaml` の `kustomize build`、policy check、CRD catalog schema を含む kubeconform、整合性チェックを実行します。

## 再構築せずに行うセットアップの振る舞い検証

```bash
python3 -m unittest discover -s automation/tests/setup -v
```

Deploy Process Validation の `setup-behavior` job と `validate.sh` で実行します。
Python 標準ライブラリと Bash・基本コマンドのみを使用し、クラスタや認証情報は不要です。
一時ディレクトリに必要な実スクリプトだけをコピーし、外部コマンドは許可リスト形式の PATH 内のテスト用 stub に置き換えます。
ローカルの `settings.toml` は読み込まず、実際の SSH・sudo・kubectl は実行しません。

| 検証対象 | CI で確認する内容 |
| --- | --- |
| `run.sh` | all の実行順序、個別入口と別名、sudo 失敗、途中失敗時の終了コードと後続停止、ログ記録 |
| `platform-deploy.sh` | リモート Bash 本文の実行、ArgoCD → Secret → root Application の順序、接続・転送・導入・Secret 作成失敗時の停止 |
| `verify.sh` | CI / VERIFY_SKIP_SSH 時に SSH と kubeconfig 書き込みを行わないこと |

これらの成功は **セットアップ全体の実構築成功の証明ではありません**。
phase1 / phase2 の本体は置き換えているため、APT・libvirt・Terraform・cloud-init・kubeadm の動作は未検証です。
bootstrap も Kubernetes API、ArgoCD の起動・同期、外部サービスとの接続を模擬しています。
特に `CI=true make phase5` の成功はライブ検証のスキップであり、クラスタ正常性を示しません。

実構築の確度をさらに上げる次の段階は、本番のネットワーク・ストレージ・認証情報を持たない
使い捨て Ubuntu 24.04 / KVM 環境で phase1 → phase2 を実行することです。
kind だけでは libvirt / cloud-init 経路の検証にはなりません。
`clean-and-deploy.sh` は既存 VM と Terraform 状態を削除するため、既存クラスタのホストで試験しないでください。

## ログ

実行ログは次に出力されます。

```text
automation/run.log
```

失敗時は `automation/run.log` と `make phase5` の出力を先に確認します。
