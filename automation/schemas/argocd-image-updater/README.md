# Image Updater の検証スキーマ

`1.3.2/imageupdater_v1alpha1.json` は公式 Helm chart `argocd-image-updater` 1.3.2
（appVersion v1.3.1）の CRD から抽出した `openAPIV3Schema` です。
旧版用の汎用 CRD カタログと異なり、`spec.namespace` はありません。

取得元: https://argoproj.github.io/argo-helm （chart: argocd-image-updater）

chart 更新時は新しい版を `helm template` し、ImageUpdater CRD の
`spec.versions[name=v1alpha1].schema.openAPIV3Schema` を同名の JSON として
chart バージョン別ディレクトリに保存します。`validate.sh` は Application の chart 版から
対応スキーマを選び、未登録の版では検証を止めます。
