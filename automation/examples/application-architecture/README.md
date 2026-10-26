# 初回切替の履歴snapshot

2026-10-24〜25にレビューした切替例を履歴として保持する。通常Applicationからは参照せず、現行運用へ適用しない。旧worker・旧起動mode等を含むため、現行構成の生成元ではない。生成器prepare-application-architecture.pyは廃止した。

現在の正本は[manifests/apps](../../../manifests/apps/)、操作は[運用手順](../../../docs/application-postgresql-cutover.md)、変更記録は[簡素化の記録](../../../docs/application-simplification-20261025.md)を参照する。media importは隣の[明示Job](../media-import/README.md)を使用する。
