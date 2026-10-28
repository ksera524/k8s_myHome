# Harbor 3世代保持の初回反映記録（2026-10-28）

## 反映内容

- 旧 `harbor-sandbox-image-cleanup` CronJobと所有JobがGitOpsのpruneで撤去されたことを確認。
- sandbox project（ID 2）のquotaを無制限から4 GiBに設定。反映時使用量は911,594,927 bytes。
- api-hubを先行対象とし、current・previous（確認できる場合）・candidateの最大3 digestを保護。
- 他8 repositoryはuntagged artifactを含め全保持。独立した定期保持実行は設定しない。
- api-hubの公開workflowにbuild ID/attempt/commit SHAタグとdefault branch HEAD確認を反映。

## 初回標準dry run

Harbor retention policy ID 1、execution ID 675がSuccess。
全9 repository・14 artifactがRETAINとなり、削除対象は0。
保持処理の実削除とGCは実行していない。

反映前のapi-hubはcurrentとlatestが同じ1 digestで、previousは不明。
確認済みの稼働版は次のとおり。

```text
sha256:ca619f4908f60cb2ab00e9c801d792171d22a4db1f7bbe11412a0e6e438f0a95
```

以後の保守では、正常稼働確認後の新digestとこの記録を用いてpreviousを指定する。
手順は [保持契約と保守コマンド](harbor-retention.md) を参照。

## 実環境で補正したAPI互換性

HarborがGETレスポンスで省略するpriority=0、disabled=false、空paramsを正規化する。
非定期実行はAPIのtrigger.kindを空文字にする。Manualを指定したpolicyの更新は実APIで拒否されるため使用しない。
これらを反映した15件の保持回帰テストが成功。

## 新workflowの公開確認

[api-hub run 40628925210](https://github.com/ksera524/api-hub/actions/runs/40628925210) が成功。
GitHub側のビルド・テスト、ARC側のversioned push、HEAD確認、latest昇格がすべて成功した。
作成されたタグは `build-40628925210-1-902dea75d2d4956d98aeb9b3b9d7df4ebd1f118d`。
新しいdigestは次のとおり。

```text
sha256:7106c516c588989572cd65d6506fb50bf272a44b322ae665de920d3e4820614f
```

公開後の保持対象はこの候補と上記の旧稼働版の2 digest。削除対象は0。
sandbox使用量は917,006,102 bytes。4 GiBの上限を維持。

公開後の標準dry runはexecution ID 676でSuccess。
GitOpsでImage Updaterとapi-hubの自動同期を復帰し、公開workflowも再開した。
自動同期は一時停止のfalseが残らないよう `enabled: true` をGitで明示した。
Image Updaterの自動書き戻しcommitは `c383faa64421dda55fa0dbe5b0767048d69f8d66`。
新版へのrollout完了、ApplicationのSynced/Healthy、PodのReadyを確認。
最終的なcurrent/candidateは新版、previousは上記旧稼働版で、保持対象は2世代・削除対象0。
公開後のdry runでは全15 artifactが保持された。
