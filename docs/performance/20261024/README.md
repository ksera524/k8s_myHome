# S3配信の変更前測定（2026-10-24）

同じPodからRustFS Service、api-hub Service、既存HTTPS Gateway（api-hub経由）を比較した。保存済みデータを読み取っただけで、objectの追加・変更・削除は行っていない。測定用PodとNetworkPolicyは終了後に削除した。

| ファイル群 | 形式・サイズ | 並列数 | 経路 | 全量取得 p50 / p95 (ms) |
|---|---|---:|---|---:|
| s3-download-cluster.jsonl | pdf 5.7 MiB | 1 | s3 | 46.04 / 73.59 |
| s3-download-cluster.jsonl | pdf 5.7 MiB | 1 | api | 50.39 / 99.15 |
| s3-download-cluster.jsonl | pdf 5.7 MiB | 1 | gateway | 121.22 / 174.63 |
| s3-download-cluster.jsonl | mp4 6.8 MiB | 1 | s3 | 78.81 / 84.88 |
| s3-download-cluster.jsonl | mp4 6.8 MiB | 1 | api | 59.46 / 72.7 |
| s3-download-cluster.jsonl | mp4 6.8 MiB | 1 | gateway | 136.16 / 177.29 |
| s3-download-cluster-parallel.jsonl | pdf 5.7 MiB | 4 | s3 | 145.47 / 174.05 |
| s3-download-cluster-parallel.jsonl | pdf 5.7 MiB | 4 | api | 271.24 / 495.51 |
| s3-download-cluster-parallel.jsonl | pdf 5.7 MiB | 4 | gateway | 442.81 / 578.59 |
| s3-download-cluster-parallel.jsonl | mp4 6.8 MiB | 4 | s3 | 229.15 / 323.21 |
| s3-download-cluster-parallel.jsonl | mp4 6.8 MiB | 4 | api | 257.45 / 381.68 |
| s3-download-cluster-parallel.jsonl | mp4 6.8 MiB | 4 | gateway | 415.69 / 1136.28 |
| s3-download-cluster-large.jsonl | pdf 28.4 MiB | 1 | s3 | 341.44 / 823.19 |
| s3-download-cluster-large.jsonl | pdf 28.4 MiB | 1 | api | 524.38 / 556.57 |
| s3-download-cluster-large.jsonl | pdf 28.4 MiB | 1 | gateway | 475.24 / 712.64 |
| s3-download-cluster-large.jsonl | mp4 70.3 MiB | 1 | s3 | 543.76 / 2124.99 |
| s3-download-cluster-large.jsonl | mp4 70.3 MiB | 1 | api | 678.01 / 795.83 |
| s3-download-cluster-large.jsonl | mp4 70.3 MiB | 1 | gateway | 1168.9 / 1543.36 |

`s3` はRustFS直接、`api` はapi-hub Service、`gateway` はHTTPS→api-hub→RustFS。新しいS3 HTTPS Gateway経路の測定結果ではない。

- 全量と先頭1 MiB Rangeを取得し、経路間のバイト数・SHA-256一致とHTTP 200/206を確認した。各サンプルのTTFB・転送時間はJSONLに保存した。
- 単独取得は各5回、並列4は各8回。少数標本のp95は参考値であり、継続的なSLOを示さない。
- 経路ごとに順番に測定しており、NFS・OSキャッシュを揃えていない。小さいMP4ではapi経由が直接取得より速い例もある。
- ローカルport-forward経由のbaselineは転送が約4 MiB/sに制限され、api-hubだけの性能評価には使用しない。
- 大きいMP4では直接取得約544 ms、既存Gateway約1169 ms。4並列でも中継経路の遅延増加が見られた。一方、端末回線やブラウザ描画はこの測定に含まれず、体感遅延の主因をapi-hubだけと断定しない。
- api-hubのアイドル5分CPUは約0.004 core。CPU throttling指標は取得できず、制限の影響がないとは判定していない。

再計測は `automation/scripts/diagnostics/s3-download-benchmark.py --help` を参照。署名URLと生object keyを結果に出さず、object IDはkeyのハッシュで匿名化している。切替後は同じ端末・objectで、新しいS3 HTTPS経路、シーク、PDF表示、署名期限切れ後の再取得を測定する。
