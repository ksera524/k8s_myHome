# プラットフォーム拡張

## Reloader

`manifests/platform/reloader/` を bootstrap の `reloader` Application (wave 10) が管理します。
Reloader は kube-system に配置し、sandbox / observability のみ監視します。
Role / RoleBinding により Secret・ConfigMap の読み取りと Deployment / DaemonSet / StatefulSet の更新を許可します。
CronJob / Job は対象外で、アノテーションを付けた workload だけを再起動します。

- API Hub: `reloader.stakater.com/auto: "true"`。参照する設定・資格情報の変更に追従。
- Alertmanager: `secret.reloader.stakater.com/reload: alertmanager-slack`。Webhook の変更に追従。
- Grafana: 初期管理者 Secret は DB 初期化用なので自動再起動の対象にしません。

annotations 戦略を使い、対象 Application の ignoreDifferences と RespectIgnoreDifferences により
`/spec/template/metadata/annotations/reloader.stakater.com~1last-reloaded-from` だけを無視します。
イメージや通常の環境変数の差分は無視しません。
対象を追加するときは workload のアノテーション、監視 namespace/RBAC、Application の差分設定を一緒に確認します。
再起動による停止時間は workload の replica / update strategy に依存します。

## Grafana とログ集約

[監視運用](observability.md#grafana--loki--alloy) を参照してください。
Grafana / Loki / Alloy は既存 observability Application (wave 11) の管理下です。
Grafana の HTTPRoute は observability-access (wave 13)、DNS は既存 publisher が管理します。
初期管理者パスワードは ESO が生成するため、新しい外部 Secret の手動登録は不要です。

## Renovate

`.github/workflows/renovate.yml` が毎日 JST 09:00 と workflow_dispatch で実行されます。
`renovate.json` が更新ルール、`.github/renovate-runner.json` が実行設定です。
常駐 Pod や新しい PAT は使わず、当該リポジトリだけを GITHUB_TOKEN で処理します。
GitHub の Settings > Actions > General > Workflow permissions で
**Allow GitHub Actions to create and approve pull requests** を有効にしてください。
organization 側で禁止されている場合は管理者による設定変更が必要です。

- 公開コンテナイメージ、外部 Argo CD Helm Chart を更新。
- GitHub Actions 自体の更新は workflow 書込権限付き GitHub App / PAT が必要になるため、
  今回の GITHUB_TOKEN 運用では対象外。
- リリースから3日待機、同時 PR は3件まで、自動マージなし。
- major は Dependency Dashboard 上の承認後に PR を作成。
- ローカル GitOps の `HEAD` と自作 Harbor イメージの `latest` は維持。
- upstream / 同梱 chart / tasks / automation は走査対象外。
- Harbor / RustFS の repo-local Helm wrapper は同梱 chart の再取得も必要です。
  ARC は Controller / Runner / ConfigMap の版を一括更新するため Renovate の Chart 更新対象外です。
  Argo CD / Gateway API の配布 URL 更新も含め、これらは
  従来の Application Version Updates workflow を手動実行して更新。
  従来 workflow の定期実行は削除し、Renovate との二重 PR を避けます。

GITHUB_TOKEN による PR イベントでは通常の CI が起動しないため、
`dispatch-renovate-validation.py` が同一 repo の github-actions[bot] 作成の
`renovate/*` PR の HEAD に `ci-deploy-validate.yml` を明示 dispatch します。
同じ SHA に run があれば重複起動せず、キャンセルされた run は次回再試行します。
この検証 run は workflow_dispatch であるため、ブランチ保護の必須チェック設定との対応も確認してください。

初回は default branch にマージ後、Renovate workflow を手動実行し、Dashboard / PR 作成と
その HEAD の検証結果を確認します。バージョン番号だけ更新できても移行手順が必要な製品は、
リリースノート・永続データ互換性を確認してから手動マージします。

## ローカル検証

```bash
nix develop --command automation/scripts/ci/validate.sh
```

Loki / Alloy の設定は各バージョンの実行イメージでも検証できます。

```bash
docker run --rm -v "$PWD/manifests/platform/observability/config:/config:ro" grafana/loki:3.7.8 -config.file=/config/loki.yaml -verify-config=true
docker run --rm -v "$PWD/manifests/platform/observability/config:/config:ro" grafana/alloy:v1.20.1 validate /config/config.alloy
```

CI の `platform-configs` job はマニフェスト内のイメージ版を読み取り、Loki / Alloy の設定と Renovate 設定を実イメージで検証します。
