# k8s_myHome アーキテクチャ概要

## システム構成

### 物理構成
```
ホストマシン (Ubuntu 24.04 LTS)
├── CPU: 8コア以上
├── メモリ: 24GB以上
└── ストレージ
    ├── システムディスク: NVMe/SSD
    └── データディスク: 外部USB/SSD (200GB以上)
```

### 仮想化レイヤー
```
QEMU/KVM + libvirt
├── ネットワーク: NAT (virbr0 - 192.168.122.0/24)
└── ストレージプール: /mnt/k8s-storage
```

### Kubernetesクラスター
```
3ノードクラスター (kubeadm v1.29.0)
├── Control Plane (192.168.122.10)
│   ├── CPU: 4コア
│   ├── メモリ: 8GB
│   └── ディスク: 50GB
└── Worker Nodes
    ├── Worker-1 (192.168.122.11)
    │   ├── CPU: 2コア
    │   ├── メモリ: 4GB
    │   └── ディスク: 30GB
    └── Worker-2 (192.168.122.12)
        ├── CPU: 2コア
        ├── メモリ: 4GB
        └── ディスク: 30GB
```

## ネットワークアーキテクチャ

### ネットワークセグメント
- **ホストネットワーク**: 192.168.122.0/24
- **Pod Network**: 10.244.0.0/16 (Flannel)
- **Service Network**: 10.96.0.0/12
- **LoadBalancer Pool**: 192.168.122.100-150 (MetalLB)

### 主要サービスIP
| サービス | IP | 用途 |
|---------|-----|-----|
| Harbor | 192.168.122.100 | プライベートコンテナレジストリ |
| NGINX Ingress | 192.168.122.101 | HTTPSエントリーポイント |
| ArgoCD | 192.168.122.102 | GitOps (将来予約) |

## プラットフォームスタック

### コアコンポーネント
1. **MetalLB**: ベアメタルLoadBalancer
2. **NGINX Ingress Controller**: L7ロードバランサー
3. **cert-manager**: 証明書管理
4. **ArgoCD**: GitOps CD
5. **Harbor**: コンテナレジストリ
6. **External Secrets Operator**: 秘密情報管理

### GitOpsアーキテクチャ
```
GitHub Repository
└── manifests/
    └── 00-bootstrap/app-of-apps.yaml
        ├── infrastructure/ (ArgoCD管理)
        ├── platform/      (ArgoCD管理)
        └── applications/  (ArgoCD管理)
```

## セキュリティアーキテクチャ

### 証明書管理
- **自己署名CA**: Harbor用
- **Let's Encrypt**: 外部公開サービス用（将来）
- **cert-manager**: 証明書のライフサイクル管理

### 秘密情報管理
```
Pulumi ESC (External)
    ↓
External Secrets Operator
    ↓
Kubernetes Secrets
    ↓
Applications
```

## CI/CDアーキテクチャ

### GitHub Actions統合
```
GitHub Repository
    ↓
Actions Runner Controller (ARC)
    ↓
Self-hosted Runners (in Kubernetes)
    ↓
Harbor Registry
```

### デプロイメントフロー
1. コード変更をGitHubにプッシュ
2. GitHub Actionsがビルド＆テスト
3. コンテナイメージをHarborにプッシュ
4. ArgoCDが変更を検知して自動デプロイ

## 高可用性考慮事項

### 現在の制限
- Control Planeは単一ノード（HA非対応）
- etcdバックアップは手動
- Harborは単一インスタンス

### 将来の拡張案
1. Control PlaneのHA化（3ノード）
2. 分散ストレージ（Rook/Ceph）
3. マルチクラスター対応
4. 外部DNS統合