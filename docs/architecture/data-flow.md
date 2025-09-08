# 🔄 データフロー

## 概要

k8s_myHomeにおけるデータフローは、GitOpsを中心とした宣言的な構成管理と、CI/CDパイプラインによる継続的デリバリーを実現しています。

## 主要データフローパターン

### 1. GitOpsデータフロー

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant GH as GitHub
    participant Argo as ArgoCD
    participant K8s as Kubernetes
    participant App as Application
    
    Dev->>GH: 1. Push manifests
    GH->>Argo: 2. Webhook/Polling
    Argo->>GH: 3. Fetch manifests
    Argo->>K8s: 4. Apply manifests
    K8s->>App: 5. Create/Update resources
    App->>Argo: 6. Report status
    Argo->>Dev: 7. Display in dashboard
```

### 2. CI/CDデータフロー

```mermaid
graph LR
    subgraph "CI Pipeline"
        Code[Source Code] --> GHA[GitHub Actions]
        GHA --> Runner[Self-hosted Runner]
        Runner --> Build[Docker Build]
        Build --> Test[Test Execution]
    end
    
    subgraph "CD Pipeline"
        Test --> Push[Push to Harbor]
        Push --> Update[Update Manifest]
        Update --> Argo[ArgoCD Sync]
        Argo --> Deploy[Deploy to K8s]
    end
    
    subgraph "Registry"
        Harbor[Harbor Registry]
        Push -.->|Image| Harbor
        Deploy -.->|Pull| Harbor
    end
```

### 3. シークレット管理フロー

```mermaid
graph TB
    subgraph "External Sources"
        Pulumi[Pulumi ESC]
        GitHub[GitHub Secrets]
    end
    
    subgraph "Kubernetes"
        ESO[External Secrets Operator]
        SecretStore[SecretStore]
        K8sSecret[Kubernetes Secret]
        Pod[Application Pod]
    end
    
    Pulumi -->|API| ESO
    GitHub -->|API| ESO
    ESO --> SecretStore
    SecretStore --> K8sSecret
    K8sSecret -->|Mount/Env| Pod
```

## 詳細データフロー

### アプリケーションデプロイメントフロー

```yaml
# 1. 開発者がマニフェストを作成
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/ksera524/k8s_myHome
    path: manifests/apps/my-app
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: sandbox
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

```mermaid
stateDiagram-v2
    [*] --> GitCommit: Developer pushes
    GitCommit --> ArgoCDDetect: Repository polling
    ArgoCDDetect --> OutOfSync: Changes detected
    OutOfSync --> Syncing: Auto-sync triggered
    Syncing --> Deploying: Apply to cluster
    Deploying --> Healthy: Resources created
    Healthy --> [*]: Deployment complete
    
    OutOfSync --> ManualSync: Manual intervention
    ManualSync --> Syncing
    
    Deploying --> Failed: Error occurred
    Failed --> OutOfSync: Rollback
```

### イメージビルド・プッシュフロー

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant GH as GitHub
    participant Runner as ARC Runner
    participant Docker as Docker
    participant Harbor as Harbor Registry
    participant K8s as Kubernetes
    
    Dev->>GH: 1. Push code
    GH->>Runner: 2. Trigger workflow
    Runner->>Runner: 3. Checkout code
    Runner->>Docker: 4. Build image
    Docker->>Docker: 5. Tag image
    Runner->>Harbor: 6. Push image
    Harbor->>Harbor: 7. Scan & store
    Runner->>GH: 8. Update manifest
    GH->>K8s: 9. ArgoCD sync
    K8s->>Harbor: 10. Pull image
    K8s->>K8s: 11. Run container
```

### ネットワークトラフィックフロー

#### Ingressトラフィック
```
1. 外部クライアント
   ↓ (DNS: *.qroksera.com)
2. Cloudflare Tunnel
   ↓ (HTTPS)
3. ホストネットワーク
   ↓ (iptables NAT)
4. MetalLB (192.168.122.100)
   ↓ (L2 Advertisement)
5. NGINX Ingress Controller
   ↓ (Host/Path routing)
6. Kubernetes Service
   ↓ (kube-proxy iptables)
7. Pod (10.244.x.x)
```

#### Pod間通信
```
Pod A (Node 1)
  ↓ (veth pair)
cni0 bridge
  ↓ (Flannel)
VXLAN tunnel (UDP 8472)
  ↓ (Overlay)
cni0 bridge (Node 2)
  ↓ (veth pair)
Pod B (Node 2)
```

### ログ・メトリクスフロー

```mermaid
graph TB
    subgraph "Data Sources"
        App[Application Logs]
        Metrics[Pod Metrics]
        Events[K8s Events]
        Audit[Audit Logs]
    end
    
    subgraph "Collection"
        Stdout[Container Stdout]
        Files[Log Files]
        API[Metrics API]
    end
    
    subgraph "Processing"
        FluentBit[Fluent Bit]
        Prometheus[Prometheus]
    end
    
    subgraph "Storage"
        ES[Elasticsearch]
        TSDB[Prometheus TSDB]
    end
    
    subgraph "Visualization"
        Kibana[Kibana]
        Grafana[Grafana]
    end
    
    App --> Stdout
    App --> Files
    Metrics --> API
    Events --> API
    Audit --> Files
    
    Stdout --> FluentBit
    Files --> FluentBit
    API --> Prometheus
    
    FluentBit --> ES
    Prometheus --> TSDB
    
    ES --> Kibana
    TSDB --> Grafana
```

### バックアップ・リストアフロー

```mermaid
sequenceDiagram
    participant Cron as CronJob
    participant Backup as Backup Script
    participant ETCD as etcd
    participant Storage as Backup Storage
    participant Admin as Administrator
    participant Restore as Restore Script
    
    Cron->>Backup: 1. Trigger backup
    Backup->>ETCD: 2. Create snapshot
    ETCD->>Backup: 3. Return snapshot
    Backup->>Storage: 4. Store snapshot
    Backup->>Storage: 5. Store PV data
    Backup->>Admin: 6. Send notification
    
    Note over Admin: Disaster occurs
    
    Admin->>Restore: 7. Initiate restore
    Restore->>Storage: 8. Retrieve backup
    Restore->>ETCD: 9. Restore snapshot
    Restore->>K8s: 10. Restore PVs
    Restore->>Admin: 11. Report status
```

## データ永続化

### PersistentVolumeフロー

```yaml
# PVC作成フロー
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: local-path
```

```mermaid
graph LR
    PVC[PVC Request] --> SC[StorageClass]
    SC --> Provisioner[local-path-provisioner]
    Provisioner --> PV[Create PV]
    PV --> Bind[Bind to PVC]
    Bind --> Mount[Mount to Pod]
    Mount --> FS[Filesystem]
```

### データベースレプリケーションフロー

```mermaid
sequenceDiagram
    participant App as Application
    participant Primary as PostgreSQL Primary
    participant Replica as PostgreSQL Replica
    participant Backup as Backup Storage
    
    App->>Primary: Write data
    Primary->>Primary: WAL write
    Primary->>Replica: Stream replication
    Replica->>Replica: Apply WAL
    Primary->>Backup: WAL archive
    
    Note over Primary: Primary fails
    
    Replica->>Replica: Promote to primary
    App->>Replica: Redirect writes
```

## セキュリティデータフロー

### 認証・認可フロー

```mermaid
sequenceDiagram
    participant User
    participant Browser
    participant Ingress as NGINX Ingress
    participant ArgoCD
    participant Dex
    participant GitHub
    participant K8s as Kubernetes API
    
    User->>Browser: 1. Access ArgoCD
    Browser->>Ingress: 2. HTTPS request
    Ingress->>ArgoCD: 3. Forward request
    ArgoCD->>Browser: 4. Redirect to login
    Browser->>Dex: 5. OAuth request
    Dex->>GitHub: 6. GitHub OAuth
    GitHub->>User: 7. Authenticate
    User->>GitHub: 8. Approve
    GitHub->>Dex: 9. Return token
    Dex->>ArgoCD: 10. JWT token
    ArgoCD->>K8s: 11. K8s API calls
    K8s->>K8s: 12. RBAC check
```

### TLS証明書フロー

```mermaid
graph TB
    subgraph "cert-manager"
        Issuer[ClusterIssuer]
        Cert[Certificate]
        Controller[cert-manager-controller]
    end
    
    subgraph "Ingress"
        Ingress[NGINX Ingress]
        Secret[TLS Secret]
    end
    
    subgraph "Client"
        Browser[Web Browser]
    end
    
    Cert -->|Request| Issuer
    Issuer -->|Generate| Controller
    Controller -->|Create| Secret
    Ingress -->|Use| Secret
    Browser -->|TLS Handshake| Ingress
```

## パフォーマンス最適化されたフロー

### イメージプルフロー最適化

```yaml
# イメージプルポリシー最適化
spec:
  containers:
  - name: app
    image: harbor.local/app:v1.2.3
    imagePullPolicy: IfNotPresent  # ローカルキャッシュ優先
  imagePullSecrets:
  - name: harbor-secret
```

```mermaid
graph LR
    Pod[Pod Creation] --> Check{Image exists?}
    Check -->|No| Pull[Pull from Harbor]
    Check -->|Yes| Cache[Use cached image]
    Pull --> Store[Store in node]
    Store --> Start[Start container]
    Cache --> Start
```

### リクエストルーティング最適化

```mermaid
graph TB
    Client[Client Request]
    
    subgraph "Edge"
        CDN[CDN Cache]
        CF[Cloudflare]
    end
    
    subgraph "Ingress Layer"
        LB[MetalLB]
        NGINX[NGINX]
        Cache[Response Cache]
    end
    
    subgraph "Service Mesh"
        SVC[K8s Service]
        EP[Endpoints]
    end
    
    subgraph "Pods"
        Pod1[Pod 1]
        Pod2[Pod 2]
        Pod3[Pod 3]
    end
    
    Client --> CDN
    CDN -->|Miss| CF
    CF --> LB
    LB --> NGINX
    NGINX --> Cache
    Cache -->|Miss| SVC
    SVC --> EP
    EP -->|Round Robin| Pod1
    EP -->|Round Robin| Pod2
    EP -->|Round Robin| Pod3
```

## 障害時のフェイルオーバーフロー

```mermaid
stateDiagram-v2
    [*] --> Normal: System healthy
    Normal --> NodeFailure: Node down detected
    NodeFailure --> PodEviction: Evict pods
    PodEviction --> Rescheduling: Find new node
    Rescheduling --> PodCreation: Create on new node
    PodCreation --> ServiceUpdate: Update endpoints
    ServiceUpdate --> Normal: Recovery complete
    
    NodeFailure --> ManualIntervention: Cannot reschedule
    ManualIntervention --> NodeAddition: Add new node
    NodeAddition --> Rescheduling
```

---
*最終更新: 2025-01-09*