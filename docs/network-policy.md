# NetworkPolicy の運用

Flannel の Pod ネットワークは維持し、`kube-network-policies` v1.1.2 を独立した
DaemonSet として ArgoCD が管理する。Application は wave 3、ポリシーの owner は
wave 2 の `core`。初回はポリシーだけを先に同期してからコントローラを追加する。
既存クラスタでは wave だけに依存せず、`core` の同期完了を確認する。

## RustFS の許可通信

| 接続元 | 接続先 | ポート |
|---|---|---|
| sandbox の app=api-hub | RustFS S3 API | TCP 9000 |
| nginx-gateway の nginx-gateway-nginx / gateway-name=nginx-gateway | RustFS console | TCP 9001 |

管理経路は Cloudflare Tunnel → cloudflared → NGINX Gateway:443 → RustFS:9001。
Namespace と Pod の selector は同一 peer 内で AND 指定する。
RustFS Namespace 内全体への許可や、未使用の home-camera-recorder の例外は設けない。
共有 Gateway の入口制限と egress 制限は今回追加しない。
このポリシーだけでは Gateway を経由したアクセスが Cloudflare 経由かは判別できない。
api-hub の presigned URL でクライアントが直接 S3 に接続する用途は許可しない。

## コントローラの前提と制約

- Linux の nftables / NFQUEUE と bridge-nf-call-iptables=1 を使用する。
- 現行ノードは NRI socket を提供していないため `--disable-nri=true`。
  Pod 情報は API informer から取得し、Pod 作成直後の情報伝播の競合は NRI で解消していない。
- `--strict-mode=true` でポリシー変更を既存接続にも反映する。
- `--fail-open=true` は可用性優先。コントローラ停止・キュー障害時は通信を通すため、
  常時 fail-closed な境界ではない。DaemonSet と metrics の監視を併用する。
- metrics の readiness は HTTP プロセスの確認であり、遮断の動作保証ではない。
  導入・更新時は許可通信と拒否通信の両方を実測する。

## 導入・検証

1. `core` を同期し、RustFS の既存の広い許可が残っていないことを確認する。
2. 初回は RustFS が稼働する worker2 に nodeSelector で限定して導入する。
3. api-hub 経由で専用の一時バケットに upload / download し、一致確認後に削除する。
4. Cloudflare 経由の console、ArgoCD、Harbor と Gateway 経由の console の応答を比較する。
5. 無関係な Pod から Service IP / Pod IP の 9000 / 9001 が拒否されることを確認する。
6. hostname の nodeSelector を除去し、全ノードで稼働・監視・疎通を確認する。

## 切り戻し

通常は問題のポリシー変更を Git revert / push し、ArgoCD の同期を確認する。
通信障害で GitOps の同期自体ができない場合は、緊急措置として
`rustfs` に一時的な ingress 全許可 NetworkPolicy を作成して復旧し、
Git 修正と同期完了後にその一時ポリシーを削除する。他 Namespace の障害は対象ごとに扱う。

コントローラ全体を停止する場合は Git 上の DaemonSet の nodeSelector に
存在しないラベル条件を追加して同期する。緊急時の手動変更では先に当該 Application の
自動同期・selfHeal を一時停止し、Git に同じ状態を反映してから自動同期を戻す。
fail-open のためプロセス終了後の NFQUEUE は bypass するが、nftables の
`inet kube-network-policies` table は残る。完全撤去時だけ各ノードでその table を確認・削除する。
他の nftables / iptables ruleset は flush しない。
