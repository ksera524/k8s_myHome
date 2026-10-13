# RSSHub

RSSHub-private のソースを GitHub Actions でビルドし、既存の Harbor / ARC / ArgoCD で運用する。

- URL: `https://rsshub.internal.qroksera.com`
- アプリリポジトリ: `https://github.com/ksera524/RSSHub-private`
- Application: `rsshub` / `rsshub-access` / `rsshub-private-runner`
- Namespace: `sandbox`
- Deployment: `rsshub-private`
- Service: `rsshub:1200`
- イメージ: `harbor.qroksera.com/sandbox/rsshub-private:latest`

## CI/CD

`automation/scripts/github-actions/add-runner.sh RSSHub-private 0 1 latest` の生成結果をベースに、アプリリポジトリへ `.github/workflows/build-and-push-RSSHub-private.yml` を配置した。ローカルの `automation/settings.toml` がない環境では、一時コピーに GitHub owner のみ設定して生成した。

生成した workflow には次の調整を加えている。再生成時にも維持すること。

- Docker イメージ名を小文字の `rsshub-private` にする。
- `linux/amd64` と `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=0` を指定し、Chromium を同梱する。
- `KUBECONFIG` を `$GITHUB_ENV` に書き込み、後続の rollout ステップへ引き継ぐ。
- Harbor ログインに `--password-stdin` を使用する。
- 手動実行と同一ブランチの実行直列化を追加する。push はアプリリポジトリの main/master のみに限定する。

GitHub-hosted runner がイメージをビルドして artifact として渡し、`rsshub-private-runners` が内部 Harbor へ push して Deployment を再起動する。pull request ではビルドのみ実行する。

Harbor の push には既存の `arc-systems/harbor-auth` を使う。`HARBOR_PROJECT` は `sandbox` が前提。pull には既存の `sandbox/harbor-registry` を使うため、イメージ参照は同 Secret の認証対象 `harbor.qroksera.com` に合わせている。push 先の `harbor.internal.qroksera.com` と同じ Harbor を参照する。

初回は k8s_myHome の変更を先に push して Runner を作り、次にアプリリポジトリの workflow を push する。初回イメージの push 完了までは RSSHub Pod が ImagePullBackOff になる場合がある。以後は master への push でビルド・配布・再起動が実行される。

## Runtime

RSSHub は Chromium 同梱イメージで動作し、`/dev/shm` に 256Mi のメモリボリュームを割り当てる。キャッシュには専用の `rsshub-redis` を使用する。Redis は最大 128Mi、LRU で破棄し、再生成可能なキャッシュのため永続化しない。

TLS 証明書は既存の cert-manager issuer が発行する。CoreDNS と Tailscale Split DNS から内部 Gateway へ解決する。Cloudflared への公開設定は追加しない。外部サイトの認証が必要なルートを使う際は、既存の ExternalSecret 運用で認証情報を別途追加する。

## 確認

```bash
kubectl get applications -n argocd rsshub rsshub-access rsshub-private-runner
kubectl rollout status deployment/rsshub-private -n sandbox --timeout=300s
kubectl logs -n sandbox deployment/rsshub-private --tail=50
curl --fail https://rsshub.internal.qroksera.com/healthz
```

DNS 設定前やクラスタ内からだけ接続する場合:

```bash
kubectl port-forward -n sandbox service/rsshub 1200:1200
curl --fail http://localhost:1200/healthz
```
