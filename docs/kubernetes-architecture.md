# Kubernetesアーキテクチャ

## 概要

k8s_myHomeは、QEMU/KVM仮想化基盤上に構築された本格的な3ノードKubernetesクラスターです。本ドキュメントでは、クラスターのアーキテクチャ、ネットワーク設計、およびコンポーネント構成について詳説します。

## クラスター構成

### ノード構成

| ノード名 | 役割 | IPアドレス | リソース | OS |
|---------|------|-----------|---------|-----|
| k8s-control-plane | Control Plane | 192.168.122.10 | 4 CPU, 8GB RAM, 50GB Disk | Ubuntu 24.04 LTS |
| k8s-worker1 | Worker Node | 192.168.122.11 | 2 CPU, 4GB RAM, 30GB Disk | Ubuntu 24.04 LTS |
| k8s-worker2 | Worker Node | 192.168.122.12 | 2 CPU, 4GB RAM, 30GB Disk | Ubuntu 24.04 LTS |

### Kubernetesバージョン

- **Kubernetes**: `automation/settings.toml` の `kubernetes.version`
- **Container Runtime**: containerd
- **CNI**: Flannel (最新版)
- **クラスター初期化**: kubeadm

## ネットワークアーキテクチャ

### ネットワークセグメント

```
┌──────────────────────────────────────────────────────┐
│              ホストネットワーク                         │
│                192.168.122.0/24                      │
├──────────────────────────────────────────────────────┤
│  Gateway: 192.168.122.1                             │
│                                                      │
│  ┌─────────────────────────────────────────────┐   │
│  │         Kubernetesノード                     │   │
│  │  - Control Plane: 192.168.122.10            │   │
│  │  - Worker1: 192.168.122.11                  │   │
│  │  - Worker2: 192.168.122.12                  │   │
│  └─────────────────────────────────────────────┘   │
│                                                      │
│  ┌─────────────────────────────────────────────┐   │
│  │       LoadBalancer IP プール                 │   │
│  │    192.168.122.100 - 192.168.122.150        │   │
│  │                                             │   │
│  │  固定IP割り当て:                             │   │
│  │  - NGINX Gateway: 192.168.122.100           │   │
│  └─────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────┘
```

### 内部ネットワーク

- **Pod Network CIDR**: 10.244.0.0/16 (Flannel)
- **Service CIDR**: 10.96.0.0/12
- **DNS**: CoreDNS (クラスター内部DNS)

## コアコンポーネント

### 1. ネットワーキング

#### MetalLB (LoadBalancer)
- **バージョン**: v0.13.12
- **モード**: Layer 2
- **IPプール**: 192.168.122.100-150
- **用途**: External LoadBalancer サービス提供

#### NGINX Gateway Fabric
- **バージョン**: 2.3.0
- **タイプ**: LoadBalancer
- **IP**: 192.168.122.100
- **用途**: Gateway API による HTTP/HTTPS ルーティング

### 2. セキュリティ

#### cert-manager
- **バージョン**: v1.13.3
- **Issuer**: self-signed (開発環境)
- **用途**: TLS証明書の自動発行・更新

#### External Secrets Operator
- **バージョン**: 0.18.2
- **Backend**: Pulumi ESC
- **用途**: 外部シークレット管理システムとの統合

### 3. GitOps

#### ArgoCD
- **デプロイ方式**: upstream `install.yaml`（stable追従）
- **パターン**: App-of-Apps
- **認証**: GitHub OAuth統合
- **同期間隔**: 3分（デフォルト）

### 4. コンテナレジストリ

#### Harbor
- **バージョン**: 1.18.0
- **URL**:
  - 内部: harbor.internal.qroksera.com (192.168.122.100)
  - 外部: harbor.qroksera.com (Cloudflare経由)
- **ストレージ**:
  - Registry: 10Gi
  - JobService Log: 1Gi
  - Database: 1Gi
  - Redis: 1Gi
  - Trivy: 5Gi
- **認証**: admin/<harbor-admin-password>（初期値は変更）

### 5. CI/CD

#### GitHub Actions Runner Controller (ARC)
- **タイプ**: Runner ScaleSet
- **設定**: 
  - minRunners: 1（推奨、設定可能）
  - maxRunners: 3（デフォルト）
- **モード**: Docker-in-Docker (dind)

## ストレージアーキテクチャ

### StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
```

### PersistentVolume構成

- **Local Path Provisioner**: 動的プロビジョニング
- **ベースパス**: /opt/local-path-provisioner
- **各ワーカーノード**: ローカルストレージ使用

## セキュリティモデル

### ネットワークポリシー

NetworkPolicyは一部導入済み（cloudflaredのIngress拒否、rustfsのGateway経由Ingress許可）。
本番運用を見据える場合は、以下を段階的に拡張します：

1. **Namespace分離**: アプリケーション間の通信制御
2. **Ingress/Egress制御**: 明示的な通信許可
3. **デフォルト拒否**: ゼロトラストモデル

### RBAC (Role-Based Access Control)

- **ServiceAccount**: 各アプリケーションに専用SA
- **Role/RoleBinding**: 最小権限の原則
- **ClusterRole**: 必要最小限のクラスター権限

## 監視・可観測性

### Grafana K8s Monitoring
- **方式**: Grafana k8s-monitoring（Helm）
- **メトリクス収集**: Prometheus Remote Write
- **ログ収集**: Loki
- **トレース収集**: OTLP
- **送信先**: Grafana Cloud

### ヘルスチェック

```bash
# クラスター状態
kubectl get nodes
kubectl get pods --all-namespaces

# API Serverの健全性
kubectl get --raw='/readyz?verbose'

# イベント確認
kubectl get events --all-namespaces
```

## 高可用性考慮事項

### 現在の制限

- **Control Plane**: シングルノード（HA非対応）
- **etcd**: シングルインスタンス
- **ストレージ**: ローカルストレージ（レプリケーションなし）

### 本番環境への推奨改善

1. **Control Plane HA**: 3ノード構成
2. **etcd クラスター**: 3または5ノード
3. **分散ストレージ**: Ceph, Longhorn等
4. **バックアップ**: Velero等によるバックアップ

## パフォーマンス最適化

### リソース配分

```yaml
# Control Plane推奨
resources:
  requests:
    cpu: 2
    memory: 4Gi
  limits:
    cpu: 4
    memory: 8Gi

# Worker Node推奨
resources:
  requests:
    cpu: 1
    memory: 2Gi
  limits:
    cpu: 2
    memory: 4Gi
```

### チューニングパラメータ

- **kube-apiserver**: `--max-requests-inflight=400`
- **kubelet**: `--max-pods=110`
- **etcd**: `--quota-backend-bytes=8589934592`

## まとめ

k8s_myHomeのKubernetesアーキテクチャは、ホームラボ環境に最適化された構成となっています。仮想化基盤上で動作する3ノードクラスターは、本番環境と同等の機能を提供しながら、リソース効率的な運用を実現しています。

GitOpsパターンの採用により、宣言的な構成管理と自動化されたデプロイメントが可能となり、開発・テスト環境として理想的なプラットフォームを提供します。
