# 切替用workload

新コードに対応する既存アプリのマニフェスト。ArgoCDの現在のsourceからは参照されていない。
新imageのHarbor digestを確定してから既存appsへ反映する。[手順](../../../docs/application-postgresql-cutover.md)を参照。

`prepare-application-architecture.py` で再生成可能。plannerはsuspend、camera StatefulSetは0 replicaで生成し、旧writerとの重複を防いでから段階的に有効にする。

```bash
nix develop --command python3 automation/scripts/diagnostics/prepare-application-architecture.py --image-tag architecture-20261024
```
