# PGO

Crunchy Postgres Operator 6.0.3 の Helm chart を同梱する。
取得元は `oci://registry.developers.crunchydata.com/crunchydata/pgo:6.0.3`、
取得時の chart digest は `sha256:0d27d9923c7393a77e1d0b9e31344d30873b1ca2c513f0f93d62764801eec7a2`。

Application `pgo`（wave 8）が Operator と CRD を所有する。
Operator は `postgres-operator` に配置し、`PGO_TARGET_NAMESPACE=database` で監視範囲を限定する。
chart の RBAC はクラスタ範囲であり、監視範囲の限定と RBAC の制限は同義ではない。
CRD の prune / delete は確認必須とし、DB の連鎖削除を防ぐ。

この段階では PostgresCluster は追加しない。Harbor は既存 DB を使用する。
現行 VM は QEMU の既定 CPU で x86-64-v2 を満たさず、UBI 9 の起動が失敗したため、
Operator は `replicas: 0` で停止している。ホスト CPU の対応を確認し、VM の CPU mode を
修正・再起動して必要な命令が公開された後に `replicas: 1` に戻す。
移行先の追加・復元・資格情報反映・Harbor 切り替えは
[移行計画](../../../tasks/shared-postgresql.md)に従って実施する。

```bash
kubectl -n postgres-operator rollout status deployment/pgo
kubectl get crd postgresclusters.postgres-operator.crunchydata.com
kubectl -n database get postgresclusters
```

更新時は chart と対応する PostgreSQL / pgBackRest イメージを一緒に確認し、
`automation/scripts/ci/validate.sh` と API server の dry-run を実施する。
