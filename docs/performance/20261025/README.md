# api-hub切替後のS3ブラウザ経路確認

2026-10-25 JST、作業端末から本番のHTTPS endpointを読み取り専用で確認した。署名URL・生object key・メディア本体は記録せず、結果はkeyのハッシュで識別する。

- `POST /s3/browser_get_object` でPDF/MP4の署名URLを取得。
- viewerのOrigin付き `Range: bytes=1024-2047` で206、1024 bytes、対応するContent-Rangeを確認。旧proxyの同じ範囲と内容一致。
- OPTIONS preflightは200で、GET/Range要求にviewerのAccess-Control-Allow-Originが返る。
- 全量取得は両経路とも200で、サイズ・SHA-256が一致。各3回、経路の測定順を交互にして比較した。

| 種別 | サイズ | 直接S3 HTTPS p50 | api-hub HTTPS proxy p50 |
|---|---:|---:|---:|
| 小PDF | 393,952 bytes | 89.70 ms | 82.12 ms |
| 小MP4 | 327,932 bytes | 105.79 ms | 82.91 ms |
| PDF | 7,984,189 bytes | 757.08 ms | 783.91 ms |
| MP4 | 8,284,905 bytes | 896.92 ms | 835.67 ms |

機能は正常だが、この端末・少数標本では直接経路の一貫した速度改善は示されていない。ブラウザのPDF描画・再生開始時間や並列取得は含まない。viewerの切替後にpreload抑制・カタログ取得を含む体感速度を確認する。2026-10-24のPod内測定とは測定元と対象objectが異なるため、前後の改善率として比較しない。

詳細は `s3-browser-small.jsonl` / `s3-browser-medium.jsonl`。署名期限切れ後の自動再取得は既存のブラウザ回帰テストで確認済みだが、今回の本番読取試験では期限切れまで待っていない。
