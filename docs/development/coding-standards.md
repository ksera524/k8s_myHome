# 📏 コーディング規約

## 概要

k8s_myHomeプロジェクトにおけるコーディング規約と品質基準を定義します。一貫性のあるコードベースを維持し、保守性を向上させることを目的としています。

## 共通原則

### SOLID原則
- **S**ingle Responsibility: 単一責任の原則
- **O**pen/Closed: 開放閉鎖の原則
- **L**iskov Substitution: リスコフの置換原則
- **I**nterface Segregation: インターフェース分離の原則
- **D**ependency Inversion: 依存性逆転の原則

### クリーンコード
```go
// Bad
func p(x int, y int) int {
    return x * y + x * 0.1
}

// Good
func calculatePriceWithTax(price int, quantity int) int {
    const taxRate = 0.1
    subtotal := price * quantity
    tax := int(float64(subtotal) * taxRate)
    return subtotal + tax
}
```

## 言語別規約

## Shell Script

### 基本ルール
```bash
#!/bin/bash
# ShellCheck準拠: shellcheck scripts/*.sh でチェック

set -euo pipefail  # エラーハンドリング
IFS=$'\n\t'       # Internal Field Separator

# グローバル変数は大文字
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="${SCRIPT_DIR}/config.toml"

# ローカル変数は小文字
function deploy_application() {
    local app_name="${1}"
    local namespace="${2:-default}"
    
    # 引数チェック
    if [[ -z "${app_name}" ]]; then
        log_error "Application name is required"
        return 1
    fi
    
    # 処理
    kubectl apply -f "${app_name}.yaml" -n "${namespace}"
}

# ログ関数
log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }
log_debug() { [[ "${DEBUG:-0}" == "1" ]] && echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') $*"; }

# エラーハンドリング
trap 'log_error "Error on line $LINENO"' ERR

# メイン処理
main() {
    log_info "Starting deployment..."
    deploy_application "my-app" "production"
    log_info "Deployment completed"
}

# スクリプト実行時のみmain関数を呼ぶ
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

### 命名規則
```bash
# 変数
GLOBAL_VARIABLE="value"        # グローバル: 大文字_スネークケース
local_variable="value"          # ローカル: 小文字_スネークケース
readonly CONSTANT_VALUE="const" # 定数: 大文字_スネークケース

# 関数
function setup_environment() {}  # 小文字_スネークケース
function _private_function() {} # プライベート: アンダースコア開始

# ファイル
setup-host.sh                   # ケバブケース
common-utils.sh                 # 共通ライブラリ
```

## YAML (Kubernetes/Helm)

### 基本構造
```yaml
# ファイルヘッダー
---
# Application: My Application
# Version: 1.0.0
# Description: Sample Kubernetes deployment
# Author: Your Name
# Date: 2025-01-09

apiVersion: apps/v1  # APIバージョンは最初
kind: Deployment     # Kindは2番目
metadata:           # メタデータは3番目
  name: my-app      # 名前はケバブケース
  namespace: production
  labels:           # ラベルは意味のあるものを
    app: my-app
    version: v1.0.0
    component: backend
    managed-by: argocd
  annotations:      # アノテーションで追加情報
    deployment.kubernetes.io/revision: "1"
    prometheus.io/scrape: "true"
    prometheus.io/port: "9090"
spec:              # 仕様は最後
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      # セキュリティコンテキスト必須
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 2000
      containers:
      - name: app
        image: my-app:v1.0.0
        imagePullPolicy: IfNotPresent
        ports:
        - name: http        # ポート名は意味のあるものを
          containerPort: 8080
          protocol: TCP
        # 環境変数
        env:
        - name: LOG_LEVEL
          value: "info"
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: url
        # リソース制限必須
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        # ヘルスチェック必須
        livenessProbe:
          httpGet:
            path: /healthz
            port: http
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: http
          initialDelaySeconds: 5
          periodSeconds: 5
        # ボリュームマウント
        volumeMounts:
        - name: config
          mountPath: /etc/config
          readOnly: true
      volumes:
      - name: config
        configMap:
          name: app-config
```

### Helm Values
```yaml
# values.yaml
# グローバル設定
global:
  imageRegistry: harbor.local
  imagePullSecrets:
    - name: harbor-secret
  storageClass: local-path

# アプリケーション設定
app:
  name: my-app
  version: 1.0.0
  
  # イメージ設定
  image:
    repository: my-app
    tag: v1.0.0  # Chartバージョンと同期
    pullPolicy: IfNotPresent
  
  # レプリカ設定
  replicaCount: 3
  
  # リソース設定（環境別にオーバーライド可能）
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
  
  # 自動スケーリング
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 80
  
  # サービス設定
  service:
    type: ClusterIP
    port: 80
    targetPort: 8080
  
  # Ingress設定
  ingress:
    enabled: true
    className: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
    hosts:
      - host: my-app.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: my-app-tls
        hosts:
          - my-app.example.com
```

## Go

### プロジェクト構造
```
cmd/
├── app/
│   └── main.go          # エントリーポイント
pkg/
├── api/
│   └── v1/              # APIバージョン
├── controller/          # コントローラー
├── service/            # ビジネスロジック
└── repository/         # データアクセス
internal/               # 内部パッケージ
├── config/
└── utils/
```

### コードスタイル
```go
package service

import (
    "context"
    "fmt"
    "time"
    
    "github.com/ksera524/k8s_myHome/pkg/api/v1"
    "k8s.io/apimachinery/pkg/types"
    "sigs.k8s.io/controller-runtime/pkg/client"
)

// PodService manages pod operations
type PodService interface {
    GetPod(ctx context.Context, key types.NamespacedName) (*v1.Pod, error)
    CreatePod(ctx context.Context, pod *v1.Pod) error
    UpdatePod(ctx context.Context, pod *v1.Pod) error
    DeletePod(ctx context.Context, key types.NamespacedName) error
}

// podService implements PodService
type podService struct {
    client client.Client
    timeout time.Duration
}

// NewPodService creates a new PodService instance
func NewPodService(client client.Client) PodService {
    return &podService{
        client:  client,
        timeout: 30 * time.Second,
    }
}

// GetPod retrieves a pod by namespaced name
func (s *podService) GetPod(ctx context.Context, key types.NamespacedName) (*v1.Pod, error) {
    // タイムアウト設定
    ctx, cancel := context.WithTimeout(ctx, s.timeout)
    defer cancel()
    
    // 入力検証
    if key.Name == "" || key.Namespace == "" {
        return nil, fmt.Errorf("invalid namespaced name: %v", key)
    }
    
    // Pod取得
    pod := &v1.Pod{}
    if err := s.client.Get(ctx, key, pod); err != nil {
        return nil, fmt.Errorf("failed to get pod %s/%s: %w", key.Namespace, key.Name, err)
    }
    
    return pod, nil
}

// エラーハンドリング
type PodError struct {
    Op  string
    Pod types.NamespacedName
    Err error
}

func (e *PodError) Error() string {
    return fmt.Sprintf("pod operation %s failed for %s/%s: %v", 
        e.Op, e.Pod.Namespace, e.Pod.Name, e.Err)
}

func (e *PodError) Unwrap() error {
    return e.Err
}
```

## Dockerfile

### マルチステージビルド
```dockerfile
# Build stage
FROM golang:1.21-alpine AS builder

# Build arguments
ARG VERSION=dev
ARG BUILD_DATE
ARG VCS_REF

# Install dependencies
RUN apk add --no-cache git ca-certificates tzdata

# Set working directory
WORKDIR /build

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-w -s \
    -X main.version=${VERSION} \
    -X main.buildDate=${BUILD_DATE} \
    -X main.gitCommit=${VCS_REF}" \
    -o app cmd/app/main.go

# Runtime stage
FROM scratch

# Labels
LABEL org.opencontainers.image.title="My Application" \
      org.opencontainers.image.description="Sample Kubernetes application" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.source="https://github.com/ksera524/k8s_myHome" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.vendor="k8s_myHome" \
      org.opencontainers.image.licenses="MIT"

# Copy from builder
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /build/app /app

# Set timezone
ENV TZ=Asia/Tokyo

# Non-root user
USER 1000:1000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/app", "health"]

# Expose port
EXPOSE 8080

# Entry point
ENTRYPOINT ["/app"]
```

## Terraform

### ファイル構成
```
infrastructure/
├── main.tf           # メインリソース定義
├── variables.tf      # 変数定義
├── outputs.tf        # 出力定義
├── versions.tf       # プロバイダーバージョン
├── terraform.tfvars  # 変数値
└── modules/
    └── vm/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

### コードスタイル
```hcl
# versions.tf
terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7.0"
    }
  }
}

# variables.tf
variable "vm_count" {
  description = "Number of VMs to create"
  type        = number
  default     = 3
  
  validation {
    condition     = var.vm_count > 0 && var.vm_count <= 10
    error_message = "VM count must be between 1 and 10."
  }
}

variable "vm_config" {
  description = "VM configuration"
  type = object({
    cpu    = number
    memory = number
    disk   = number
  })
  
  default = {
    cpu    = 2
    memory = 4096
    disk   = 30
  }
}

# main.tf
locals {
  common_tags = {
    Environment = var.environment
    Project     = "k8s_myHome"
    ManagedBy   = "Terraform"
    CreatedAt   = timestamp()
  }
}

# リソース定義
resource "libvirt_domain" "vm" {
  count = var.vm_count
  
  name   = format("k8s-node-%02d", count.index + 1)
  memory = var.vm_config.memory
  vcpu   = var.vm_config.cpu
  
  network_interface {
    network_name = "default"
    wait_for_lease = true
  }
  
  disk {
    volume_id = libvirt_volume.vm_disk[count.index].id
  }
  
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }
  
  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
  
  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      graphics,
      console
    ]
  }
}

# outputs.tf
output "vm_ips" {
  description = "IP addresses of created VMs"
  value       = libvirt_domain.vm[*].network_interface[0].addresses[0]
}
```

## Git

### .gitignore
```gitignore
# Binaries
*.exe
*.dll
*.so
*.dylib
/bin/
/dist/

# Test binary
*.test
*.out

# Dependencies
/vendor/
/node_modules/

# IDE
.idea/
.vscode/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Terraform
*.tfstate
*.tfstate.*
.terraform/
*.tfplan

# Kubernetes
kubeconfig
*.kubeconfig

# Secrets
*.key
*.pem
*.crt
secrets.yaml
.env

# Logs
*.log
/logs/

# Temporary
/tmp/
/temp/
```

### Pre-commit hooks
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files
      - id: check-merge-conflict
      
  - repo: https://github.com/koalaman/shellcheck-precommit
    rev: v0.9.0
    hooks:
      - id: shellcheck
        
  - repo: https://github.com/adrienverge/yamllint
    rev: v1.33.0
    hooks:
      - id: yamllint
        args: ['-d', '{extends: default, rules: {line-length: {max: 120}}}']
        
  - repo: https://github.com/golangci/golangci-lint
    rev: v1.55.2
    hooks:
      - id: golangci-lint
        
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.86.0
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
```

## テスト

### ユニットテスト命名
```go
// テスト関数名: Test<関数名>_<シナリオ>
func TestGetPod_Success(t *testing.T) {}
func TestGetPod_NotFound(t *testing.T) {}
func TestGetPod_InvalidInput(t *testing.T) {}

// テーブルドリブンテスト
func TestCalculatePrice(t *testing.T) {
    tests := []struct {
        name     string
        price    int
        quantity int
        want     int
        wantErr  bool
    }{
        {
            name:     "normal case",
            price:    100,
            quantity: 2,
            want:     200,
            wantErr:  false,
        },
        {
            name:     "zero quantity",
            price:    100,
            quantity: 0,
            want:     0,
            wantErr:  false,
        },
        {
            name:     "negative price",
            price:    -100,
            quantity: 2,
            want:     0,
            wantErr:  true,
        },
    }
    
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got, err := CalculatePrice(tt.price, tt.quantity)
            if (err != nil) != tt.wantErr {
                t.Errorf("CalculatePrice() error = %v, wantErr %v", err, tt.wantErr)
                return
            }
            if got != tt.want {
                t.Errorf("CalculatePrice() = %v, want %v", got, tt.want)
            }
        })
    }
}
```

## セキュリティ

### シークレット管理
```yaml
# 絶対にコミットしない
apiVersion: v1
kind: Secret
metadata:
  name: database-secret
type: Opaque
data:
  # Base64エンコードされた値
  username: YWRtaW4=  # admin
  password: cGFzc3dvcmQxMjM=  # password123

# 代わりにExternal Secretsを使用
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: database-secret
spec:
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: database-secret
  data:
    - secretKey: username
      remoteRef:
        key: database/creds
        property: username
    - secretKey: password
      remoteRef:
        key: database/creds
        property: password
```

### セキュアコーディング
```go
// SQL Injection対策
// Bad
query := fmt.Sprintf("SELECT * FROM users WHERE id = %s", userID)

// Good
query := "SELECT * FROM users WHERE id = ?"
rows, err := db.Query(query, userID)

// パスワード保存
// Bad
password := "plaintext"

// Good
import "golang.org/x/crypto/bcrypt"
hashedPassword, _ := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
```

## パフォーマンス

### リソース最適化
```yaml
# リソース要求と制限の適切な設定
resources:
  requests:  # 最小保証リソース
    cpu: 100m
    memory: 128Mi
  limits:    # 最大使用可能リソース
    cpu: 500m
    memory: 512Mi
```

### キャッシング
```go
// メモリキャッシュ実装
type Cache struct {
    mu    sync.RWMutex
    items map[string]*Item
}

func (c *Cache) Get(key string) (*Item, bool) {
    c.mu.RLock()
    defer c.mu.RUnlock()
    item, found := c.items[key]
    return item, found
}

func (c *Cache) Set(key string, item *Item) {
    c.mu.Lock()
    defer c.mu.Unlock()
    c.items[key] = item
}
```

---
*最終更新: 2025-01-09*