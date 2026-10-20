# アプリの追加と配布

アプリ実体は [apps/](../manifests/apps/)、公開経路は [access/](../manifests/access/) に置きます。
Application の namespace と source は [一覧](diagrams/app-of-apps-sync-wave.md) が参照先です。
現在のユーザーアプリは api-hub、blog、cooklog、hitomi、hitomi-pdf、hitomi-upload-viewer、home-camera、rsshub、selenium。
selenium は `tools`、それ以外は `sandbox` に配置します。

## 新規追加

1. `manifests/apps/<app>/` に workload / Service と `kustomization.yaml` を作成します。
2. `bootstrap/applications/user-apps/<app>-app.yaml` を作成し、同ディレクトリの Kustomization に登録します。
   既存例の Project `apps`、Git revision `HEAD`、wave 12 を基準にします。
3. 必要な Namespace / AppProject destination、共有設定、ExternalSecret、PVC を用意します。
4. hostname を公開する場合は [access 手順](access.md#新しく到達可能な-api-を追加する手順) に沿って
   contract / Route / 証明書 / DNS / access Application を追加します。
5. [静的検証](reference.md) を実行し、Git 反映後に Application と実際のサービス操作を確認します。

イメージはベース YAML だけでなく、Kustomize の `images` で上書きされる場合があります。
更新対象は `kustomize build manifests/apps/<app>` の最終出力で確認します。

## 現行の sandbox 配布

[Runner 生成スクリプト](../automation/scripts/github-actions/add-runner.sh) は `STRATEGY=latest` のみを受け付けます。
生成 workflow の経路は GitHub-hosted runner で build → artifact → ARC runner で Harbor へ push →
sandbox の Deployment を `rollout restart` です。PR イベントでは build までです。

これは固定 tag をインフラ PR で更新する方式と異なり、**同じ Git revision / `latest` でも稼働イメージが変わります**。
ArgoCD の Synced は最新 digest の稼働を証明しません。新規 Pod の imageID とアプリの動作も確認します。
アプリ側リポジトリの workflow の実際の配置・改変内容は、このリポジトリだけでは確認できません。

CI policy は `apps/`・namespace `sandbox`・`harbor.qroksera.com/sandbox/` の条件下で first-party の `latest` を許容します。
固定版へ移行する場合は manifest とアプリ側 workflow を一緒に変更します。

## Runner を追加する

設定の `[github].username` を用意し、PyYAML を含む toolchain で実行します。

```bash
nix develop .#default
make add-runner REPO=my-app MIN=0 MAX=1 STRATEGY=latest
# settings.toml の arc_repositories から一括生成する場合
make add-runners-all
```

変更先は [runners-appset.yaml](../manifests/platform/ci-cd/github-actions/runners-appset.yaml) です。
**Make 経由の workflow 出力先は `automation/scripts/github-actions/.github/workflows/build-and-push-<repo>.yml`** です。
Make がスクリプトのディレクトリへ移動し、スクリプトが相対パスで出力するためです。
生成物は Git 非追跡なので、内容を確認してアプリリポジトリの `.github/workflows/` に配置します。

生成後に確認する点:

- Docker イメージ名は repo 名をそのまま使うため、大文字を含む repo では小文字への調整が必要です。
- `KUBECONFIG` の export は生成 workflow の 1 step 内だけです。後続 step でも使うには `$GITHUB_ENV` 等への引き継ぎが必要です。
- Deployment 名は repo の小文字化と `.` / `_` の置換から導出します。CronJob は再起動対象になりません。
- Harbor の認証処理を確認し、アプリ側では `--password-stdin` で渡す形に整えます。

Runner 定義の Git 反映と ArgoCD 同期後、アプリ側の workflow を実行します。
[RBAC](../manifests/platform/ci-cd/github-actions/github-actions-rbac.yaml) は `harbor-auth` の読み取りと
sandbox Deployment の get / list / watch / patch を許可しています。
controller の手動 Helm 導入は不要です。

```bash
kubectl -n arc-systems get autoscalingrunnersets,pods
kubectl -n argocd get applications
kubectl -n sandbox get pods -o wide
```
