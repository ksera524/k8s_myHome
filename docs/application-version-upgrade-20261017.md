# Kubernetes アプリケーション更新（2026-10-17）

Git の宣言を基準に、公式 Helm index・GitHub Releases・コンテナレジストリを照合した。
稼働クラスタの実バージョン調査やデプロイは実施していない。以下は確認時点の安定版への更新。

## 更新一覧

| 対象 | 更新前 | 更新後 | 確認元 |
| --- | --- | --- | --- |
| cert-manager (chart) | `v1.19.3` | `v1.21.2` | [公式](https://charts.jetstack.io) |
| tailscale-operator (chart) | `1.94.2` | `1.104.1` | [公式](https://pkgs.tailscale.com/helmcharts) |
| metallb (chart) | `0.15.3` | `0.16.1` | [公式](https://metallb.github.io/metallb) |
| external-secrets (chart) | `2.0.0` | `2.13.0` | [公式](https://charts.external-secrets.io) |
| harbor (chart) | `1.18.2` | `1.19.4` | [公式](https://helm.goharbor.io) |
| rustfs (chart) | `0.0.83` | `1.0.2` | [公式](https://charts.rustfs.com) |
| ARC Controller / Runner chart | `0.13.1` | `0.15.0` | [公式](https://github.com/actions/actions-runner-controller/releases/tag/gha-runner-scale-set-0.15.0) |
| VictoriaMetrics / vmalert | `v1.115.0` | `v1.154.0` | [公式](https://github.com/VictoriaMetrics/VictoriaMetrics/releases/tag/v1.154.0) |
| Alertmanager | `v0.28.1` | `v0.34.1` | [公式](https://github.com/prometheus/alertmanager/releases/tag/v0.34.1) |
| kube-state-metrics | `v2.15.0` | `v2.20.0` | [公式](https://github.com/kubernetes/kube-state-metrics/releases/tag/v2.20.0) |
| cloudflared | `2026.1.2` | `2026.10.1` | [公式](https://github.com/cloudflare/cloudflared/releases/tag/2026.10.1) |
| CoreDNS (Tailnet Split DNS) | `v1.11.1` | `v1.14.7` | [公式](https://github.com/coredns/coredns/releases/tag/v1.14.7) |
| local-path-provisioner | `v0.0.34` | `v0.0.37` | [公式](https://github.com/rancher/local-path-provisioner/releases/tag/v0.0.37) |
| Selenium standalone Chrome | `145.0-20260222` | `155.0-20261010` | [公式](https://github.com/SeleniumHQ/docker-selenium/releases/tag/4.51.0-20261010) |
| Redis (RSSHub cache) | `7-alpine` | `8.10.2-alpine` | [公式](https://github.com/redis/redis/releases/tag/8.10.2) |
| AWS CLI (RustFS lifecycle) | `2.27.49` | `2.38.1` | [公式](https://github.com/aws/aws-cli/tree/2.38.1) |
| Python (週次レポート / Harbor cleanup) | `3.13.7-slim-bookworm / 3.12-slim` | `3.15.0-slim-bookworm` | [公式](https://github.com/docker-library/official-images/blob/master/library/python) |
| Argo CD bootstrap / ApplicationSet CRD | `v3.3.0 (bootstrap)` | `v3.5.5` | [公式](https://github.com/argoproj/argo-cd/releases/tag/v3.5.5) |
| pause (オプトイン node-mutations) | `gcr.io/google_containers/pause:3.2` | `registry.k8s.io/pause:3.10.2` | [公式](https://registry.k8s.io/v2/pause/tags/list) |

Harbor chart 1.19.4 は Harbor 2.15.4、RustFS chart 1.0.2 は RustFS 1.0.2 を使用する。
Harbor / RustFS はリポジトリ内の同梱チャートも公式配布物に置き換えた。

## 更新不要・比較対象外

- NFS Subdir External Provisioner chart 4.0.18、NGINX Gateway Fabric 2.8.0、Gateway API 1.6.3、kube-network-policies 1.1.2 は確認時点で最新。
- api-hub、blog、cooklog、hitomi、hitomi-pdf、hitomi-upload-viewer、home-camera、rsshub-private は最終的なマニフェストが private Harbor の `latest` を参照する。公開された版番号と比較できないため変更しない。blog / cooklog のベースに残る `0.0.1` は Kustomize で `latest` に上書きされる。
- Actions Runner の `latest`、Docker の `dind`、BusyBox のタグなし / `stable` は可変タグ。タグの変更による版上げの対象外であり、稼働Podが最新digestかは未確認。
- Kubernetes本体、containerd、ホスト側ツール、CI Actionsは今回のアプリ更新スコープ外。

## 互換性と適用時の確認

- **Argo CD:** 本体・全CRDを `argocd-core` のGitOps管理に移行し、同期で v3.5.5 を適用する。bootstrapも同じ固定版を読む。以降は[定期更新PR](application-auto-updates.md)で追従する。[3.3→3.4](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.3-3.4/) と [3.4→3.5](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.4-3.5/) の変更を確認。利用するchart配布先はHTTPS/OCI TLS。Helm 4同梱への変更に留意する。
- **ARC:** Controller、Runner chart、生成スクリプトが読むConfigMapを0.15.0で統一。chartに存在しない `crds.install` 設定を除去し、`skipCrds: false` で同版CRDをArgo CDのServerSideApplyに含める。更新後はRunner登録とジョブ実行を確認する。
- **MetalLB:** L2Advertisementのみの構成に合わせて `frrk8s.enabled: false` を明示。[0.16で既定化したFRR-K8s](https://metallb.universe.tf/release-notes/#version-0-16-0)を追加起動しない。metricsはHTTPS化したが、本構成はMetalLBのscrapeAnnotations/ServiceMonitorを有効化していない。
- **Harbor / RustFS:** 新旧chartの生成結果で、リソース名、Deployment/StatefulSetのselector、PVC spec、StatefulSetのvolumeClaimTemplatesの一致を確認。既存Secret参照も維持。適用前にHarbor DBとregistry、RustFSのデータ・メタデータをバックアップする。データ移行後は単純なタグ巻き戻しで復旧できると仮定せず、旧版への復帰にはバックアップ復元を準備する。RustFSはalpha.83から1.0.2への更新なので、S3 PUT/GET、既存オブジェクト、認証、署名付きURL、lifecycleを実環境で確認する。
- **監視:** VictoriaMetrics/vmalertを同版へ更新。kube-state-metricsは既存の明示的な `--resources` とCRS設定を維持するため、新規collector用の権限追加は不要。更新後にscrape、既存アラート、週次レポートを確認する。VictoriaMetricsのデータも事前にバックアップする。
- **Redis:** `emptyDir` の再生成可能キャッシュであり、永続RDB/AOFの移行はない。再起動時にキャッシュは失われる。
- **Python:** 両ジョブを3.15.0に統一し、Debian bookworm版を使用。標準ライブラリのみを使用するスクリプト。
- **pause:** 非既定の `node-mutations/` 内の補助コンテナのみ更新。通常のHarborデプロイにオプトインを追加していない。

## 検証

- `nix develop -c bash automation/scripts/ci/validate.sh`: 成功（setupテスト9件、actionlint、shellcheck、yamllint、policy、全Kustomize build / kubeconform、consistency）。最終のARC設定変更も個別に再生成・検証した。
- 直接Helmを参照するApplicationのvaluesでchartをrenderし、kubeconformで検証。ARC Controller / Runnerも0.15.0でrender。未登録のCRDスキーマは `-ignore-missing-schemas` によりスキップするため、実クラスタでのAPI受理まで保証するものではない。
- Python 3.15.0コンテナ（ネットワーク無効）: 週次レポートの既存テスト5件成功、Harbor cleanupの構文・import成功（cleanup処理は未実行）。
- Alertmanager 0.34.1 `amtool check-config`: 成功。
- vmalert 1.154.0 `-dryRun`: 成功。既存のPrometheus形式テストは `vmalert-tool-prod unittest -disableAlertgroupLabel -files=automation/tests/observability/alert-rules.test.yaml` で成功。
- 直接更新する公開コンテナタグのmanifest存在をregistry APIで確認。
- 自前の変更の `git diff --check` は成功。同梱chartは上流配布物を維持しているため、上流由来の末尾空白/末尾空行5件はそのまま。

クラスタへのapply、bootstrap、Argo CD syncは実行していない。
