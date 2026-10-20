# Kubernetes マニフェスト

配置と所有の正本は [配置規約](../docs/manifests.md)、Application ごとの source は
[App-of-Apps 一覧](../docs/diagrams/app-of-apps-sync-wave.md) を参照してください。

初回は [bootstrap](../docs/bootstrap.md) で ArgoCD と root Application を導入します。
通常の変更は Git に反映し、各 child Application が同期します。
ディレクトリの存在だけで管理対象を判断せず、Application の source と Kustomization の登録を確認します。

```bash
# リポジトリのルートで、適用せず描画を確認
kustomize build manifests/core
kustomize build --enable-helm manifests/platform/harbor
```

- [アプリ追加](../docs/app-delivery.md)
- [公開経路](../docs/access.md)
- [Secret 管理](../docs/secrets.md)
- [検証](../docs/reference.md)
