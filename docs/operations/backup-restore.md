# 💾 バックアップ・リストアガイド

## 概要

k8s_myHomeシステムの包括的なバックアップとリストア手順を説明します。本番環境での運用を想定し、RPO（Recovery Point Objective）とRTO（Recovery Time Objective）を考慮した設計になっています。

## バックアップ戦略

### バックアップ対象と優先度

| 優先度 | 対象 | バックアップ頻度 | 保持期間 | RPO |
|-------|------|-----------------|----------|-----|
| **Critical** | etcd データ | 日次 | 30日 | 24時間 |
| **Critical** | PersistentVolumes | 日次 | 30日 | 24時間 |
| **High** | Kubernetes設定 | 週次 | 90日 | 7日 |
| **High** | VM イメージ | 週次 | 30日 | 7日 |
| **Medium** | Harbor レジストリ | 日次 | 14日 | 24時間 |
| **Medium** | ArgoCD 設定 | 変更時 | 永続 | Git管理 |
| **Low** | ログ・メトリクス | 日次 | 7日 | 24時間 |

## バックアップ実装

### 1. 自動バックアップスクリプト

```bash
#!/bin/bash
# /usr/local/bin/k8s-backup.sh

set -e

# 設定
BACKUP_DIR="/backup/k8s_myHome"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${DATE}"
RETENTION_DAYS=30

# バックアップディレクトリ作成
mkdir -p "${BACKUP_PATH}"

# ログ関数
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${BACKUP_PATH}/backup.log"
}

log "バックアップ開始: ${DATE}"

# 1. etcdバックアップ
backup_etcd() {
    log "etcdバックアップ開始..."
    
    ssh k8suser@192.168.122.10 "
        sudo ETCDCTL_API=3 etcdctl \
            --endpoints=https://127.0.0.1:2379 \
            --cacert=/etc/kubernetes/pki/etcd/ca.crt \
            --cert=/etc/kubernetes/pki/etcd/server.crt \
            --key=/etc/kubernetes/pki/etcd/server.key \
            snapshot save /tmp/etcd-snapshot-${DATE}.db
    "
    
    scp k8suser@192.168.122.10:/tmp/etcd-snapshot-${DATE}.db \
        "${BACKUP_PATH}/etcd-snapshot.db"
    
    ssh k8suser@192.168.122.10 "rm /tmp/etcd-snapshot-${DATE}.db"
    
    log "etcdバックアップ完了"
}

# 2. Kubernetes設定バックアップ
backup_k8s_config() {
    log "Kubernetes設定バックアップ開始..."
    
    # 重要な設定ファイル
    ssh k8suser@192.168.122.10 "
        sudo tar czf /tmp/k8s-config-${DATE}.tar.gz \
            /etc/kubernetes/ \
            /var/lib/kubelet/config.yaml \
            /etc/cni/
    "
    
    scp k8suser@192.168.122.10:/tmp/k8s-config-${DATE}.tar.gz \
        "${BACKUP_PATH}/k8s-config.tar.gz"
    
    ssh k8suser@192.168.122.10 "rm /tmp/k8s-config-${DATE}.tar.gz"
    
    log "Kubernetes設定バックアップ完了"
}

# 3. リソース定義バックアップ
backup_resources() {
    log "リソース定義バックアップ開始..."
    
    # すべてのリソースをYAMLで保存
    kubectl get all,cm,secret,pv,pvc,ingress,crd \
        --all-namespaces \
        -o yaml > "${BACKUP_PATH}/all-resources.yaml"
    
    # Namespace別にバックアップ
    for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
        mkdir -p "${BACKUP_PATH}/namespaces/${ns}"
        kubectl get all,cm,secret,pvc,ingress \
            -n "${ns}" \
            -o yaml > "${BACKUP_PATH}/namespaces/${ns}/resources.yaml"
    done
    
    log "リソース定義バックアップ完了"
}

# 4. PersistentVolumeデータバックアップ
backup_pv_data() {
    log "PVデータバックアップ開始..."
    
    # 各ワーカーノードのPVデータ
    for node in 192.168.122.11 192.168.122.12; do
        ssh k8suser@${node} "
            sudo tar czf /tmp/pv-data-${DATE}.tar.gz \
                /opt/local-path-provisioner/
        " || true
        
        scp k8suser@${node}:/tmp/pv-data-${DATE}.tar.gz \
            "${BACKUP_PATH}/pv-data-$(echo $node | cut -d. -f4).tar.gz" || true
        
        ssh k8suser@${node} "rm -f /tmp/pv-data-${DATE}.tar.gz" || true
    done
    
    log "PVデータバックアップ完了"
}

# 5. Harbor データバックアップ
backup_harbor() {
    log "Harborバックアップ開始..."
    
    # Harbor データベースダンプ
    kubectl exec -n harbor \
        $(kubectl get pod -n harbor -l component=database -o jsonpath='{.items[0].metadata.name}') \
        -- pg_dump -U postgres registry > "${BACKUP_PATH}/harbor-db.sql"
    
    # Harbor 設定
    kubectl get cm,secret -n harbor -o yaml > "${BACKUP_PATH}/harbor-config.yaml"
    
    log "Harborバックアップ完了"
}

# 6. VM スナップショット
backup_vms() {
    log "VMスナップショット開始..."
    
    for vm in k8s-control-plane-1 k8s-worker-1 k8s-worker-2; do
        sudo virsh snapshot-create-as ${vm} \
            --name "backup-${DATE}" \
            --description "Automated backup ${DATE}" \
            --disk-only \
            --atomic
    done
    
    log "VMスナップショット完了"
}

# 実行
backup_etcd
backup_k8s_config
backup_resources
backup_pv_data
backup_harbor
backup_vms

# 圧縮
log "バックアップ圧縮中..."
cd "${BACKUP_DIR}"
tar czf "${DATE}.tar.gz" "${DATE}/"
rm -rf "${DATE}/"

# 古いバックアップ削除
log "古いバックアップ削除中..."
find "${BACKUP_DIR}" -name "*.tar.gz" -mtime +${RETENTION_DAYS} -delete

log "バックアップ完了: ${BACKUP_PATH}.tar.gz"
```

### 2. Cronジョブ設定

```bash
# crontab -e
# 毎日午前2時にバックアップ実行
0 2 * * * /usr/local/bin/k8s-backup.sh >> /var/log/k8s-backup.log 2>&1

# 週次フルバックアップ（日曜日午前3時）
0 3 * * 0 /usr/local/bin/k8s-full-backup.sh >> /var/log/k8s-backup.log 2>&1
```

### 3. Kubernetes CronJobによるバックアップ

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: etcd-backup
  namespace: kube-system
spec:
  schedule: "0 2 * * *"  # 毎日午前2時
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: k8s.gcr.io/etcd:3.5.9-0
            command:
            - /bin/sh
            - -c
            - |
              etcdctl --endpoints=https://etcd-0:2379 \
                --cacert=/etc/kubernetes/pki/etcd/ca.crt \
                --cert=/etc/kubernetes/pki/etcd/server.crt \
                --key=/etc/kubernetes/pki/etcd/server.key \
                snapshot save /backup/etcd-$(date +%Y%m%d-%H%M%S).db
            volumeMounts:
            - name: etcd-certs
              mountPath: /etc/kubernetes/pki/etcd
            - name: backup
              mountPath: /backup
          volumes:
          - name: etcd-certs
            hostPath:
              path: /etc/kubernetes/pki/etcd
          - name: backup
            persistentVolumeClaim:
              claimName: backup-pvc
          restartPolicy: OnFailure
          nodeSelector:
            node-role.kubernetes.io/control-plane: "true"
          tolerations:
          - key: node-role.kubernetes.io/control-plane
            operator: Exists
            effect: NoSchedule
```

## リストア手順

### 1. 完全リストア（災害復旧）

```bash
#!/bin/bash
# /usr/local/bin/k8s-restore.sh

set -e

# 設定
BACKUP_FILE=$1
RESTORE_DIR="/tmp/restore"

if [ -z "$BACKUP_FILE" ]; then
    echo "使用方法: $0 <backup-file.tar.gz>"
    exit 1
fi

# ログ関数
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "リストア開始: ${BACKUP_FILE}"

# バックアップ展開
mkdir -p "${RESTORE_DIR}"
tar xzf "${BACKUP_FILE}" -C "${RESTORE_DIR}"
BACKUP_PATH=$(find "${RESTORE_DIR}" -mindepth 1 -maxdepth 1 -type d)

# 1. VMリストア（必要な場合）
restore_vms() {
    log "VM環境再作成..."
    
    cd /home/user/k8s_myHome/automation/infrastructure
    terraform destroy -auto-approve
    terraform apply -auto-approve
    
    # クラスター初期化待機
    sleep 300
    
    log "VM環境再作成完了"
}

# 2. etcdリストア
restore_etcd() {
    log "etcdリストア開始..."
    
    # etcdを停止
    ssh k8suser@192.168.122.10 "
        sudo systemctl stop etcd
        sudo rm -rf /var/lib/etcd/member
    "
    
    # スナップショットからリストア
    scp "${BACKUP_PATH}/etcd-snapshot.db" k8suser@192.168.122.10:/tmp/
    
    ssh k8suser@192.168.122.10 "
        sudo ETCDCTL_API=3 etcdctl snapshot restore /tmp/etcd-snapshot.db \
            --name k8s-control-plane-1 \
            --initial-cluster k8s-control-plane-1=https://192.168.122.10:2380 \
            --initial-advertise-peer-urls https://192.168.122.10:2380 \
            --data-dir /var/lib/etcd
        
        sudo chown -R etcd:etcd /var/lib/etcd
        sudo systemctl start etcd
    "
    
    log "etcdリストア完了"
}

# 3. Kubernetes設定リストア
restore_k8s_config() {
    log "Kubernetes設定リストア開始..."
    
    scp "${BACKUP_PATH}/k8s-config.tar.gz" k8suser@192.168.122.10:/tmp/
    
    ssh k8suser@192.168.122.10 "
        sudo tar xzf /tmp/k8s-config.tar.gz -C /
        sudo systemctl restart kubelet
    "
    
    # ワーカーノードも同様に
    for node in 192.168.122.11 192.168.122.12; do
        scp "${BACKUP_PATH}/k8s-config.tar.gz" k8suser@${node}:/tmp/
        ssh k8suser@${node} "
            sudo tar xzf /tmp/k8s-config.tar.gz -C / --exclude='pki/*'
            sudo systemctl restart kubelet
        "
    done
    
    log "Kubernetes設定リストア完了"
}

# 4. PVデータリストア
restore_pv_data() {
    log "PVデータリストア開始..."
    
    for i in 1 2; do
        node_ip="192.168.122.1${i}"
        if [ -f "${BACKUP_PATH}/pv-data-${i}.tar.gz" ]; then
            scp "${BACKUP_PATH}/pv-data-${i}.tar.gz" k8suser@${node_ip}:/tmp/
            ssh k8suser@${node_ip} "
                sudo tar xzf /tmp/pv-data-${i}.tar.gz -C /
            "
        fi
    done
    
    log "PVデータリストア完了"
}

# 5. リソースリストア
restore_resources() {
    log "リソースリストア開始..."
    
    # CRDから先にリストア
    kubectl apply -f "${BACKUP_PATH}/all-resources.yaml" \
        --dry-run=client -o yaml | \
        grep -A 1000 "kind: CustomResourceDefinition" | \
        kubectl apply -f -
    
    # その他のリソース
    kubectl apply -f "${BACKUP_PATH}/all-resources.yaml" \
        --dry-run=client -o yaml | \
        kubectl apply -f -
    
    log "リソースリストア完了"
}

# 実行確認
read -p "リストアを実行しますか？ [y/N]: " confirm
if [ "$confirm" != "y" ]; then
    echo "中止しました"
    exit 0
fi

# リストア実行
restore_etcd
restore_k8s_config
restore_pv_data
restore_resources

log "リストア完了"
```

### 2. 部分リストア

#### 特定Namespaceのリストア
```bash
# Namespace単位でリストア
kubectl apply -f /backup/namespaces/harbor/resources.yaml
```

#### 特定アプリケーションのリストア
```bash
# Deploymentとその関連リソース
kubectl apply -f - <<EOF
$(grep -A 50 "name: my-app" /backup/all-resources.yaml)
EOF
```

#### PVCデータのみリストア
```bash
# 特定PVCのデータリストア
PVC_NAME="harbor-database"
NODE_IP=$(kubectl get pv $(kubectl get pvc ${PVC_NAME} -o jsonpath='{.spec.volumeName}') \
    -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}')

ssh k8suser@${NODE_IP} "
    sudo tar xzf /backup/pv-data.tar.gz \
        -C / \
        opt/local-path-provisioner/pvc-*${PVC_NAME}*
"
```

## リストア検証

### 1. 検証チェックリスト

```bash
#!/bin/bash
# リストア後の検証スクリプト

echo "=== リストア検証 ==="

# 1. ノード状態
echo "1. ノード状態確認"
kubectl get nodes
echo ""

# 2. システムPod
echo "2. システムPod確認"
kubectl get pods -n kube-system
echo ""

# 3. etcd健全性
echo "3. etcd健全性確認"
kubectl exec -n kube-system etcd-k8s-control-plane-1 -- \
    etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    endpoint health
echo ""

# 4. アプリケーション
echo "4. アプリケーション状態"
kubectl get deployments --all-namespaces
echo ""

# 5. PVC
echo "5. PVC状態"
kubectl get pvc --all-namespaces
echo ""

# 6. サービス疎通
echo "6. サービス疎通確認"
kubectl get svc --all-namespaces | grep LoadBalancer
echo ""

echo "=== 検証完了 ==="
```

### 2. アプリケーション動作確認

```bash
# ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443
# ブラウザで https://localhost:8080 アクセス

# Harbor
curl -I http://192.168.122.100

# アプリケーションエンドポイント
for app in $(kubectl get ingress --all-namespaces -o jsonpath='{.items[*].spec.rules[*].host}'); do
    echo "Testing: $app"
    curl -I https://$app
done
```

## バックアップベストプラクティス

### 1. 3-2-1ルール
- **3つ**のバックアップコピー
- **2つ**の異なるメディア
- **1つ**のオフサイトバックアップ

### 2. 定期テスト
```yaml
# 月次リストアテスト
apiVersion: batch/v1
kind: CronJob
metadata:
  name: restore-test
spec:
  schedule: "0 0 1 * *"  # 毎月1日
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: test
            image: busybox
            command: ["/bin/sh", "-c", "echo 'Restore test reminder'"]
```

### 3. 監視とアラート
```yaml
# Prometheusアラートルール
groups:
- name: backup
  rules:
  - alert: BackupFailed
    expr: backup_last_success_timestamp < time() - 86400
    for: 1h
    annotations:
      summary: "Backup has not succeeded in 24 hours"
  
  - alert: BackupStorageFull
    expr: backup_storage_usage_percent > 90
    for: 30m
    annotations:
      summary: "Backup storage is over 90% full"
```

## 災害復旧シナリオ

### シナリオ1: コントロールプレーン障害
```bash
# 1. 影響確認
kubectl get nodes

# 2. etcdメンバー確認
etcdctl member list

# 3. 新コントロールプレーン追加
kubeadm join --control-plane

# 4. etcdリストア（必要な場合）
./k8s-restore.sh etcd-only
```

### シナリオ2: 完全障害
```bash
# 1. インフラ再構築
cd automation/infrastructure
terraform apply

# 2. フルリストア
./k8s-restore.sh /backup/latest.tar.gz

# 3. 検証
./verify-restore.sh
```

### シナリオ3: データ破損
```bash
# 1. 影響範囲特定
kubectl get events --all-namespaces

# 2. 部分リストア
./k8s-restore.sh --partial --namespace affected-namespace

# 3. データ整合性確認
kubectl exec -n affected-namespace -- app-health-check
```

---
*最終更新: 2025-01-09*