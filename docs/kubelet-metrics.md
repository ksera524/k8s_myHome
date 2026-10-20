# kubelet metrics の最小権限化

VictoriaMetrics は kubelet の `/metrics` と `/metrics/resource` を直接収集する。
`nodes/metrics` の `get` はこの収集に必要な権限で、`nodes/proxy` は不要になる。
API server の `/api/v1/nodes/<node>/proxy/...` に接続する構成では、この削減はできない。

## マージ・初回同期の前提

**既存クラスタでは、以下の証明書準備を全ノードで完了してから収集設定をマージする。**
ArgoCD の自動同期で ConfigMap と RBAC が反映されるため、先にマージすると収集が失敗する。
この手順はノード設定変更を含む。PR の作成・CI の実行だけでは実施されない。

- kubelet の認証は Webhook 有効、匿名アクセス無効、認可は Webhook とする。
- 各ノードの 10250 番で、クラスタ CA が署名し、接続先 InternalIP を SAN に持つ証明書を配信する。
- VictoriaMetrics Pod から各ノードの TCP 10250 へ到達できること。
- この repo の IPv4 構成を対象とする。IPv6 化時は scrape の `__address__` に角括弧を付ける変更も必要。

2026-10-20 の調査では全3ノードが認証・認可の条件を満たしたが、証明書はノード固有の
発行者で DNS SAN のみだった。`insecure_skip_verify` による回避はしない。

## 証明書の準備

新規クラスタでは `automation/infrastructure/main.tf` の kubeadm 設定が
`serverTLSBootstrap: true` を指定する。初回の serving CSR 承認は以下と同様に必要。
既存クラスタを移行するために Terraform のリソースを再作成してはいけない。

既存クラスタは次の順で移行する。ノードの変更は1台ずつ行い、その都度 Ready と証明書を確認する。

1. `kube-system/kubelet-config` ConfigMap をバックアップし、`data.kubelet` 内の
   `KubeletConfiguration` に `serverTLSBootstrap: true` を設定する。
   `tlsCertFile` / `tlsPrivateKeyFile` に旧証明書への固定参照があれば削除する。
   kubeadm upgrade / join 時にもこの構成が使われるよう、クラスタ側も更新する。
2. 対象ノードの `/var/lib/kubelet/config.yaml` をバックアップし、同じ変更を行う。
   systemd unit / drop-in / kubelet の起動引数にも `--tls-cert-file` / `--tls-private-key-file`
   の固定指定がないことを確認する。クライアント認証用 kubeconfig や鍵は変更・削除しない。
3. `sudo systemctl restart kubelet` を実行する。
4. 対象ノードが生成した CSR を検査する。

```bash
kubectl get csr
CSR=<対象のCSR名>
kubectl get csr "$CSR" -o yaml
kubectl get csr "$CSR" -o jsonpath='{.spec.request}' \
  | base64 -d | openssl req -noout -text
kubectl get nodes -o wide
```

確認する内容:

- signerName は `kubernetes.io/kubelet-serving`。
- requestor と CSR の CN は `system:node:<対象ノード名>`、Organization は `system:nodes`。
- SAN は対象ノードの DNS 名 / InternalIP と一致し、他ノードの名前・IP を含まない。
- usages はサーバー認証用で、クライアント認証用ではない。

確認済みの CSR だけを個別に承認する。一括承認や未検証 CSR の自動承認はしない。

```bash
kubectl certificate approve "$CSR"
kubectl wait --for=condition=Ready node/<対象ノード名> --timeout=120s
```

5. 実際に配信された証明書を CA と IP の両方で検証する。以下は管理端末で行う
   TLS の事前確認であり、Pod からの通信確認は別途必要。

```bash
kubectl -n observability get configmap kube-root-ca.crt \
  -o jsonpath='{.data.ca\.crt}' > /tmp/kubelet-metrics-ca.crt
NODE_IP=192.168.122.10 # .11 / .12 でも実施
openssl s_client -connect "${NODE_IP}:10250" \
  -CAfile /tmp/kubelet-metrics-ca.crt -verify_ip "$NODE_IP" \
  -verify_return_error </dev/null
```

`Verify return code: 0 (ok)` を確認する。旧証明書のままなら固定パス・起動引数・kubelet のログを調べる。
必要に応じて正しい設定で再起動し、証明書配信を再確認する。
既存の API server proxy 経由の収集も維持されていることを確認してから次のノードへ進む。

## GitOps で収集と権限を切り替える

全ノードの準備後、収集設定と RBAC をマージし、`observability` Application の同期を確認する。
ConfigMap はボリュームへ伝播後、VictoriaMetrics が30秒間隔で再読込する。
RBAC と ConfigMap の反映には時間差があり、一時的な scrape 失敗があり得る。

- 接続先: ノードの InternalIP:10250。
- 認証: Pod に投影された ServiceAccount token。外部へ取り出さない。
- TLS: クラスタ CA 検証を維持。
- RBAC: `nodes/metrics` は `get` のみ。`nodes` / `pods` は探索用に `get/list/watch`。
- 既存の job 名・`node`・`instance` ラベルと metric フィルターを維持する。
  `instance` は時系列互換のため従来の `kubernetes.default.svc:443` を維持し、ノード識別には `node` を使う。

```bash
SA=system:serviceaccount:observability:victoria-metrics
kubectl auth can-i get nodes/metrics --as="$SA"     # yes
kubectl auth can-i get nodes/proxy --as="$SA"       # no
kubectl auth can-i create nodes/proxy --as="$SA"    # no
kubectl -n argocd get application observability
kubectl -n observability port-forward svc/victoria-metrics 18428:8428
```

VMUI / `/targets` とクエリ API で以下を確認する。port-forward は VictoriaMetrics の状態確認に使い、
実際の scrape が Pod → kubelet の TLS・認証・通信の検証になる。

- `up{job=~"kubelet-volume-stats|kubelet-resources"}` が全3ノード・両ジョブで `1`。
  直近の scrape 成功日時と対象 URL が各ノードの 10250 番であることも確認する。
- `kubelet_volume_stats_capacity_bytes` 等が移行前と同じ PVC で更新される。
  元から容量未報告の PVC を新たな障害と誤認しない。
- `node_cpu_usage_seconds_total`、`pod_memory_working_set_bytes` 等が更新される。
- Grafana の CPU・メモリ・容量、週次レポートの dry-run が正常。
- kubelet の認可キャッシュ（調査時は許可5分）が失効した後も収集でき、旧 proxy 権限がないこと。

## 証明書の更新と復旧

serving CSR は標準の controller では自動承認されない。更新時も CSR を検査して承認する必要がある。
定期保守で Pending CSR と各ノードの配信証明書の有効期限を確認し、期限前に承認する。
本変更は承認 controller や期限監視を追加しない。自動化する場合はノードの identity・SAN を
検証する仕組みを別途設計する。

証明書移行中に問題が起きた場合は、対象ノードの設定をバックアップへ戻して kubelet を再起動し、
既存経路の収集・Node Ready を確認する。証明書の秘密鍵は削除しない。

GitOps 切り替え後の問題では、まず TLS・到達性・権限・scrape エラーを確認する。
緊急に旧経路へ戻す場合は **scrape 設定と RBAC の両方**を Git revert して同期する。
これは `nodes/proxy` のリスクを再導入する暫定復旧なので、修正後に再び削除する。
署名済み serving 証明書は旧経路でも使えるため、収集の切り戻しで元に戻す必要はない。

参考:

- [kubelet の認証・認可](https://kubernetes.io/docs/reference/access-authn-authz/kubelet-authn-authz/)
- [kubeadm の serving 証明書設定](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/#enabling-signed-kubelet-serving-certificates)
