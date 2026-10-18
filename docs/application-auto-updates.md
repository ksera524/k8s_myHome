# アプリの安定版追従

定期更新は `.github/workflows/renovate.yml` に移行しました。
毎日 JST 09:00 に公開イメージ・外部 Helm Application の更新 PR を作成し、
PR の HEAD に検証 workflow を起動します。**マージは手動**です。
Renovate の対象・除外・権限は[プラットフォーム拡張](platform-extensions.md#renovate)を参照してください。

以下は `.github/workflows/weekly-version-audit.yml`（Application Version Updates）を
**手動実行する場合**の手順です。同梱 chart の再取得、ARC の複数定義の一括更新、
Argo CD / Gateway API の配布 URL 更新を含む保守用に残しています。
メジャー版も候補に含めるため、リリースノート・データ移行・バックアップを確認してからマージします。

## 手動 updater の対象

`automation/scripts/ci/version-audit.py` が `manifests/` の宣言を読み取る。

- Helm Application: HTTP index / OCI registryから最新安定chartを選択する。
- Harbor / RustFS: Kustomizeのchart版と同梱chart全体を更新する。Secretテンプレートも必要。
- ARC: Controller、Runner、生成用ConfigMapを一括更新する。元の版が不一致なら失敗する。
- コンテナ: 固定タグをregistryの公開タグと比較し、更新先manifestの存在も確認する。
  Pythonの `slim-bookworm`、Redisの `alpine` などのvariantを維持する。
  Seleniumのブラウザ版・ビルド日は数値比較する。AWS CLIは公式Git tagsとECR Public manifestを照合する。
- Argo CD / Gateway API: バージョン固定された配布URLを公式最新安定releaseへ更新する。
- prereleaseを選ばず、現在の版より古い版へ戻さない。取得失敗・未対応のタグ形式は処理を失敗させる。

private Harborの独自アプリ、`latest` / `stable` / `dind` / タグなし、digest固定、
Kubernetes本体・containerd・CI Actionsは対象外。可変タグは稼働Podのdigest一致を保証しない。
Helmが管理する配下のイメージはchartと一緒に更新し、同梱chart内を個別に書き換えない。

## Argo CDの自己管理

`argocd-core`（wave 1）は `manifests/platform/argocd-config/` を同期する。
`upstream/kustomization.yaml` の公式 `install.yaml` が本体・全CRDを含むため、
ApplicationSet CRDの別コピーは置かない。ローカル設定はpatchとして重ね、
`server.insecure: "true"` も宣言してGatewayでのTLS終端を維持する。

bootstrapは同じupstream URLからtagを読み取る。初回導入後の版上げに `make bootstrap` は不要。
既存の `prune: false` を維持するので、上流がリソースを廃止した場合の削除は別途確認する。
自己管理への初回移行では、既存Argo CDのリソース所有権・Secret・ログイン・同期を実クラスタで確認する。

## 検証とGitHubの設定

更新候補を生成した後、Gitの追跡対象だけを一時ディレクトリに展開し、
`automation/scripts/ci/validate.sh` を実行する。失敗した候補はpushしない。
チェック済みの差分がある場合だけPRを作成・更新し、マージやクラスタ直接操作は行わない。

追加PATや外部アプリは不要で、組み込み `GITHUB_TOKEN` を使う。
リポジトリの **Settings → Actions → General → Allow GitHub Actions to create and approve pull requests**
を有効にする必要がある（このworkflowはレビューの自動承認を実行しない）。
権限はworkflowに `contents: write`、`pull-requests: write`、`actions: write` を宣言する。

[GITHUB_TOKENによる通常のpush/PRは後続workflowを起動しない](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow)。
そのため、更新ブランチを指定して `Deploy Process Validation` の `workflow_dispatch` を明示的に起動し、
PRのhead commitに対する `validate` / `setup-behavior` を確認する。
Renovate の定期処理は default branch にマージ後に有効になる。

## 手動実行

読み取りだけの調査:

```bash
nix develop --command python3 automation/scripts/ci/version-audit.py
```

ローカルで更新候補を生成（作業ツリーが変わるため専用ブランチを使用）:

```bash
nix develop --command python3 automation/scripts/ci/version-audit.py --apply
nix develop --command automation/scripts/ci/validate.sh
```

GitHub上で更新PR作成まで実行:

```bash
gh workflow run weekly-version-audit.yml
```

監査結果はworkflowのsummaryとartifactに残る。更新ブランチはbot専用とし、手修正は別PRで行う。
API障害・新しいchartの破壊的変更等で失敗した場合はActionsログを確認し、設定調整後に再実行する。
監査結果のMarkdownファイルは生成物のためGitには含めない。
