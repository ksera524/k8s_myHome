# hitomi・mediaの失敗整理（2026-10-28 JST）

実装単位①原因記録・履歴保存、②管理操作、③通知・運用を本番へ反映した。

## 配備した変更

| 対象 | ソースcommit | 配備digest |
|---|---|---|
| hitomi | `5e16747` | `sha256:bed4a6c1ebdd41fd2eca4a3b3d2a72f1b216d91899e44412d26e937b3ce65958` |
| media | `98ba400` | `sha256:32319e1ae62a5b195807ecdb6e79ad1651adbe6e07d0fa3d067aed40de7a6e3f` |
| viewer | `98ba400` | `sha256:c0bee7cf79aed0dbc47afb31aa620aba6839ca604c90f4be806e61683ceb80da` |
| 通知ルール | `b2cd8ed` | observabilityのConfigMapとvmalertをGitOpsで更新 |

hitomi/mediaはPreSync Jobでmigration 3を適用し、Image UpdaterのGit書戻しとArgoCDで配備した。直接のimage差替えは行っていない。

## 原因が分かっている失敗

| 対象ID | 現在の扱い | 調査結果・次の対応 |
|---|---|---|
| hitomi 6839 | 確認済み、failedのまま | タグ取得待機時間超過。galleryinfoとDOMの反映・待機条件を調査・修正して限定再実行 |
| hitomi 12859, 12860, 12863 | 確認済み、retryを継続 | タグ要素の文字列が空。取得元データとDOMの状態を調査・修正して限定再実行 |
| media 26893, 26897, 26898, 26899 | 確認済み、failedのまま | TwiHubのリダイレクト過多。URL解決・追従処理を修正した後、この4件だけ再実行 |

確認理由と次の対応を各失敗記録へ保存した。mediaは実際のfailed件数4を維持したまま、unreviewed=0 / acknowledged=4となることをAPI・画面・VictoriaMetricsで確認した。取得元消失の根拠がないため、対象外には変更していない。上記の根本原因の修正は別作業である。

旧DBに実際の失敗日時がなかったため、移行された記録の初回日時は移行時の観測日時。移行前に削除されたエラーの復元は行えない。

## 原因不明だった3件の個別再実行

失敗ID・versionを確認して1件ずつ理由付きで再受付し、指定item IDだけを処理した。通常収集・新着発見・他IDのclaimは行っていない。

| item ID | 再実行Job | 結果 |
|---|---|---|
| 2525 | hitomi-recover-2525-20261028-v2 | タグ未登録を確認し、既存ルールどおりfiltered / no-tags-v1 |
| 3389 | hitomi-recover-3389-20261028 | タグ未登録を確認し、既存ルールどおりfiltered / no-tags-v1 |
| 3396 | hitomi-recover-3396-20261028 | タグ未登録を確認し、既存ルールどおりfiltered / no-tags-v1 |

これは現在の再処理結果であり、詳細の失われた元の失敗原因を断定するものではない。旧失敗履歴は閉じて保持する。

最初の2525用Jobではコンテナcommandを指定し忘れ、起動前に停止した。itemはpending / attempts=0のままで、業務処理・通知は発生していなかった。commandを補ったv2で完了し、誤起動Jobは削除した。運用JobではDockerのCMDに引数を追加する際も、Kubernetes側に次を明示する。

```yaml
command: [/app/hitomi]
args: [--process-item, '2525']
```

## 検証

- Rustの通常テスト・APIテスト、隔離PostgreSQLでの移行・レビュー・再実行・保持期限・claimのテストが成功。
- viewerのビルドとブラウザテスト、理由必須・選択IDとversion・途中競合の表示を確認。
- promtoolの全ルールテスト、監視のPythonテスト7件、yamllint、Kustomize描画、kubeconformの39リソース検証が成功。
- GitHub Actionsのhitomi/mediaのbuild・recovery-tests・pushが成功。
- 本番Gateway経由の管理画面で、確認済みのmedia 4件の表示を確認。
- 新規失敗の検知・確認での解除・再発での再通知をルールテストで検証。旧exporterへのフォールバックも維持。


最終状態はhitomi_itemsのunreviewed=0 / acknowledged=4、hitomi_sourcesのunreviewed=0、mediaのunreviewed=0 / acknowledged=4。対象外は0件。取得系の未確認項目の最古滞留時間は両キューとも0秒。3件の個別再実行JobはすべてCompleteで、hitomi / hitomi-pdf / hitomi-upload-viewer / observabilityはSynced / Healthyを確認した。

最終評価でApplicationQueueFailed / ApplicationUnreviewedFailure / ApplicationQueueBacklogはすべてhealth=ok・inactive・alertsなしとなった。生のfailed件数を0へ書き換えた結果ではなく、確認状態を通知へ反映した結果である。
