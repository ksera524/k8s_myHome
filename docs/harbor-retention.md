# Harborの容量と3世代保持

## 保持契約

イメージrepositoryごとに、異なるdigestを最大3世代保持します。
同じdigestに複数の役割・タグが付いていても1世代です。

| 役割 | 保持する版 | 更新条件 |
|---|---|---|
| current | 現在Synced/Healthyで稼働する版 | デプロイ成功確認後 |
| previous | 直前に正常稼働を確認した版 | 次の版の成功確認後。失敗時は維持 |
| candidate | `latest`が指す次の候補 | default branch HEADの公開成功後 |

初期移行時にpreviousを確認できない場合は推測せず未設定とします。
成功記録として時刻・Application名・Git revision・digestを運用記録に残し、次回のpreviousを指定します。
currentへ戻す切り戻しでも、その前に正常稼働していた版をpreviousとして明示します。
単純な「最新ビルド3件」や「最近pullされた3件」は、この契約の代用にはしません。

この上限は**保持処理完了後**の対象です。push中・GC待ちのデータは一時的に増えます。
稼働状態が不明、デプロイ失敗、切替途中、実行中の旧Podがある場合は削除を停止します。
安全確認のため停止した場合は3世代への収束が遅れますが、容量上限を緩めたり保護対象を削除したりしません。

## 容量上限

sandbox projectの上限は **4 GiB (4,294,967,296 bytes)** とします。
既存設定がこれより厳しい場合は維持します。上限到達時は新しいpushが失敗します。
2026-10-28の読み取り確認では、sandboxは911,594,927 bytes（約869 MiB）、9 repository、容量制限なしでした。
現時点の使用量の3倍（約2.55 GiB）と、新規push・GC待ちの余裕を見込んだ初期値です。
既存の版数やレイヤ共有率が異なるため、将来の3世代のサイズを保証する算定ではありません。

Harborのproject quotaは全project・NFSの物理容量を制限するものではありません。
Registry PVCの要求容量10 GiBとproject quotaを混同しないでください。
quota使用量とストレージ空き容量を保守時に確認します。
容量不足時はGCと異常なイメージサイズを確認し、4 GiBを超える変更は保持契約の変更としてレビューします。

## 実装と初期移行

[retention.py](../automation/scripts/harbor/retention.py) が、ArgoCDとworkload/Pod、Harborを照合してplanを作成します。
初期対象はapi-hubだけです。他repoは、untagged artifactも含め全保持する標準ルールを設定します。
OCI index、非IMAGE artifact、可変タグだけのworkloadは対象外として停止します。
他repoへの展開は、各repoの公開workflow・成功判定・実行中Jobを確認してから行います。

旧 `harbor-sandbox-image-cleanup` CronJobはGitOps定義から撤去します。
反映時にCronJobがpruneされ、実行中・再試行待ちのJobが残っていないことを確認してください。
旧処理はlatest以外を削除するため、新しい保持方式と併用できません。
削除を停止する移行期間は、一時的に保持数が増えることを容量監視で扱います。

標準保持ルールは手動実行とし、独立した定期実行は設定しません。
Harbor APIでは非定期実行を `trigger.kind: ""` で表します。`Manual` は更新APIで拒否されるため使いません。
Harborは配布状態を知らず、公開・Image Updater・ArgoCDと保持処理を独立に動かすと配布途中の版を削除し得ます。
まず保守時間に下記コマンドを使います。常駐PodやRunnerのKubernetes権限は追加しません。
公開からデプロイ成功までの役割更新と排他制御を自動化できるまで、日次自動削除は開始しません。

## 読み取り確認

ローカルでKubernetes管理用contextを確認し、Harbor管理用資格情報を保護したファイルで用意します。
資格情報はコマンド引数・Git・planに含めません。TLS検証は有効です。
疎通にport-forwardを使う場合は、別端末で次を実行します。

```bash
kubectl -n harbor port-forward service/harbor-core 18080:80
```

別端末で、シェルの履歴にパスワードを入れずに実行します。
以下のURLはlocalhostへのport-forward専用です。通常のアクセスにはHTTPS URLを使います。

```bash
export HARBOR_USERNAME=admin
export HARBOR_PASSWORD_FILE=/secure/path/harbor-password
python3 automation/scripts/harbor/retention.py \
  --url http://127.0.0.1:18080 \
  --no-previous-known --output /tmp/harbor-plan.json
```

前版が確認できている場合は `--no-previous-known` の代わりに
`--previous sha256:<正常稼働を確認した64桁のdigest>` を指定します。
既存artifactの作成日時だけからpreviousを選ばないでください。
planは新規ファイルにだけ出力します。current/previous/candidate、keep/delete、容量・生成policyをレビューします。

## 反映と標準dry run

1. 対象アプリの公開workflowを停止し、待機中・実行中・再試行待ちのpush jobがないことを確認します。
2. Image Updaterの対象 `applicationRefs` をGitで一時的に外し、同期と処理終了を確認します。
3. 対象Applicationの自動同期をGitで一時停止し、現在の同期が完了したことを確認します。
   手動の配布・切り戻し・タグ変更も保持処理完了まで停止します。
4. 旧cleanupのCronJobと残存Jobがないこと、既存の定期保持処理・GCが停止していることを確認します。
5. この状態で読み取りplanを取り直し、次を実行します。

```bash
python3 automation/scripts/harbor/retention.py \
  --url http://127.0.0.1:18080 \
  --no-previous-known --output /tmp/harbor-apply.json \
  --reviewed-plan /tmp/harbor-plan.json --apply --maintenance
```

`--maintenance` は上記停止の確認を表す引数です。コマンド自身はworkflowやGitOpsを停止しません。
対象digestに `retain-<digestの64桁>` タグを付け、標準保持ルールと容量上限を設定し、標準dry runの完了を待ちます。
これは設定を書き換えますがartifactは削除しません。標準保持はタグの一致でartifact全体を保持するため、
SHA/buildタグや古いretainタグが残っていても、今回指定したdigest以外を保持する理由にはなりません。

projectに既存policyがある場合は自動上書きしません。
Harbor API `GET /api/v2.0/retentions/<id>` のJSONを保存・レビューし、
`--replace-policy /secure/path/existing-policy.json` を指定します。現在値と一致するときだけ置換します。
他repoを全保持するため、既存の他repo削除ルールは継承しません。
標準ルールの結合はORです。既存ルールへ単に追記する方式は使いません。

## 削除・GC・再開

Harbor UIの保持処理dry runログで、削除対象がplanのdeleteと一致し、他repoが保持されることを確認します。
停止状態を維持したまま、同じ引数に `--delete` を追加し、新しい `--output` を指定します。
既存policyは上記の方法で取得し `--replace-policy` に渡します。
コマンドは再度状態とpolicyを確認し、dry run成功後に標準保持処理を実行して完了を待ちます。
独自のartifact DELETEループは使いません。失敗・タイムアウト時は公開停止を維持し、Harborの実行履歴を確認します。

GCは全projectに作用するため、コマンドから自動実行しません。
Harbor UIでGCのdry run結果を確認してからGCを実行し、成功・容量回収を確認します。
不要データの回収後、ArgoCD自動同期、Image Updater、公開workflowをGitOps管理へ戻します。
次回の保持処理前に役割とplanを更新します。古いpolicyを単独で再実行しないでください。
保持失敗・容量増加時はこの手順で再実行し、旧CronJobへは戻しません。

## 検証と残作業

回帰テストは `automation/tests/ci/test_harbor_retention.py`、生成workflowの検証は
`automation/tests/ci/test_runner_delivery.py` で実行します。
実環境での4版連続公開、デプロイ失敗、直前版への切り戻し、標準dry run・保持・GC後の容量回収は、
このGit変更を反映してから保守時間内に検証します。
2026-10-28の初回読み取りではapi-hubはcurrentとlatestが同じ1世代（5,411,177 bytes）で、削除対象はありませんでした。
前版は不明であり、切り戻し可能とは扱いません。

初回反映の実行ID・容量・稼働版は [2026-10-28の反映記録](harbor-retention-20261028.md) に残しています。
