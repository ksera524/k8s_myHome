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
ArgoCD の固定版は `manifests/platform/argocd-config/upstream/kustomization.yaml` を正本とし、
bootstrap も同じ tag を読み取ります。初回導入後は `argocd-core` Application が本体・CRD・設定を管理するため、
通常のバージョン更新に `make bootstrap` の再実行は不要です。
更新PRの作成は[定期更新](application-auto-updates.md)で自動化します。

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

`automation/scripts/ci/validate.sh` は actionlint、setup / version update / 監視レポート / GitOps 検証の回帰テスト、shellcheck、yamllint、GitOps 参照・登録チェック、policy check、全 `manifests/**/kustomization.yaml` の `kustomize build` と CRD catalog schema を含む kubeconform、整合性チェックを実行します。

PR の `Deploy Process Validation` で同じ入口を実行します。GitOps チェックは次を検出します。

- このリポジトリを参照する bootstrap Application の `targetRevision` が `HEAD` 以外（multi-source も対象）。
- source path の参照切れ・リポジトリ外への参照・Kustomization / Chart.yaml の欠落。
- `directory.include` のファイル欠落。現行構成に合わせて単一ファイル指定のみ対応し、glob は検証エラーにします。
- `manifests/apps/<app>/` に実体があるのに bootstrap Application が存在しない。
- Application YAML が存在しても、`manifests/bootstrap/applications` の Kustomize 出力に含まれない登録漏れ。

チェック自身は一時リポジトリと実際の Kustomize を使って正常系・異常系をテストします。

```bash
nix develop .#default --command python3 -m unittest discover -s automation/tests/ci -v
nix develop .#default --command python3 automation/scripts/ci/gitops-check.py
```

外部 Helm chart の実際の同期、クラスタ上の admission、外部接続はこの静的検証の対象外です。
kubeconform は引き続き schema のないリソースをスキップします。
マージの強制ブロックには、GitHub 側の ruleset / branch protection で `validate` を必須チェックに設定する必要があります。

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

## GitHub Actions での実構築テスト

Actions の **Setup Integration (disposable VMs)** → **Run workflow** で手動実行します。
CLI では `gh workflow run setup-integration.yml --ref main` です。
PR ごとの自動実行は行いません。

`ubuntu-24.04` の GitHub-hosted runner 内で libvirt を準備し、共通の
`automation/infrastructure/*.tf` と cloud-init を変更せず一時ディレクトリへコピーして適用します。
設定はCI専用に生成し、VMは control-plane 3GiB + worker 2GiB × 2、各2 vCPUです。
SSH鍵とTerraform状態も一時領域に置き、NFSマウントは `enable_nfs_mount=false` で無効にします。
本番の設定・Secret・kubeconfig は不要です。
Ubuntu 24.04 の libvirt / AppArmor によるイメージの読み取り拒否を回避するため、
使い捨てrunner内だけでCI用イメージ名に限定したAppArmorルールを追加します。
AppArmorは有効のままです。

成功条件は次のすべてです。

- Terraform apply（VM作成・cloud-init・kubeadm init/join・CNI導入）が成功する。
- 3ノードすべてがReadyになり、CoreDNSが起動する。
- worker2のPodからDNSを解決し、Service経由でworker1のHTTP Podにアクセスできる。
- Terraformの再適用前後で `plan -detailed-exitcode` が0（差分なし）になる。
  差分がある場合は再適用せず失敗させる。
- worker1、worker2、control-planeを順に再起動し、各VMのboot IDが変わる。
  containerd/kubelet、IP転送、bridge設定、swap無効化が再起動後も維持される。
- 再起動後に3ノードReadyとCoreDNS復旧を確認し、新しいclient PodでDNS・ノード間HTTP通信を再検証する。
- 再起動後もTerraformの再適用前後に差分がない。

再適用の確認はTerraform管理リソースが対象です。作成時のprovisionerを再実行する検証ではありません。
VMの静的IPはcloud-initで設定し、libvirt domainの `network_interface.addresses` には重複指定しません。
DHCP leaseのない静的IPを同属性に指定すると、状態の再取得で恒常的な差分が生じます。
再起動検証は復旧を確認するもので、単一control-planeの無停止性や障害時のPod再配置は保証しません。

成功・失敗にかかわらず診断情報の収集と `terraform destroy` を試みます。
`setup-integration-diagnostics` artifactにはVM一覧、各VMのcloud-init状態、サービス状態、
ノード・Pod・イベント・通信テスト結果を7日間保存します。
イメージのファイル権限と、そのパスに対するlibvirtのAppArmor拒否も保存します。
秘密鍵、joinコマンド、Terraform状態、認証情報を含みうる全ログはartifactに含めません。
destroy失敗時もGitHub-hosted runner自体が破棄されます。

GitHubのネスト仮想化は[公式サポート対象外](https://docs.github.com/en/actions/concepts/runners/github-hosted-runners)です。
冒頭でKVM APIによるVM作成、メモリ12GiB以上、空き容量10GiB以上を確認し、不足なら失敗させます。
KVMを利用できない場合をテスト成功として扱いません。

このテストは共通Terraformからの構築を検証します。phase1のホストセットアップ、
`clean-and-deploy.sh` の既存環境削除・権限修復、NFS、ArgoCD以降のGitOps収束は対象外です。
UbuntuイメージとFlannelは現行Terraformの可変URLを使うため、外部配布物の変更でも結果が変わります。
`make all` 全体や本番の再構築成功を保証するものではありません。
`clean-and-deploy.sh` は既存 VM と Terraform 状態を削除するため、既存クラスタのホストで試験しないでください。

## ログ

実行ログは次に出力されます。

```text
automation/run.log
```

失敗時は `automation/run.log` と `make phase5` の出力を先に確認します。
