# Phase 3: k8s構築（Ansible）

kubeadmを使用してControl Plane 1台 + Worker Node 2台のk8sクラスタを自動構築します。

## 概要

Phase 2で構築されたVM環境に対して、以下のk8sコンポーネントを自動インストール・設定します：

- **kubeadm cluster**: Control Plane + Worker Node 2台
- **Container Runtime**: containerd (systemd cgroup対応)
- **CNI**: Flannel (Pod間通信)
- **kubectl**: 管理コマンド設定

## 前提条件

Phase 2のVM構築が完了していることを確認：

```bash
# VM状態確認
sudo virsh list --all

# SSH接続確認
ssh k8suser@192.168.122.10 'hostname && sudo cloud-init status'
ssh k8suser@192.168.122.11 'hostname && sudo cloud-init status'
ssh k8suser@192.168.122.12 'hostname && sudo cloud-init status'
```

## 🚀 実行方法

### ワンコマンド実行（推奨）

```bash
# k8sクラスタ自動構築
./k8s-deploy.sh
```

### 手動実行

```bash
# 1. Ansible接続テスト
ansible -i inventory.ini all -m ping

# 2. k8sクラスタ構築実行
ansible-playbook -i inventory.ini k8s-setup.yml

# 3. 構築結果確認
cat k8s-cluster-info.txt
```

## ファイル構成

```
automation/ansible/
├── README.md              # このファイル
├── inventory.ini          # Ansibleインベントリ（VM接続情報）
├── k8s-setup.yml         # k8sクラスタ構築Playbook
├── k8s-deploy.sh         # 自動実行スクリプト（推奨）
└── roles/                # Ansible Roles（必要に応じて）
```

## 構築内容

### Phase 3.1: Control Plane初期化
- containerd設定（systemd cgroup有効化）
- kubeadm init実行
- kubectl設定
- Worker Node用join-token生成

### Phase 3.2: Worker Node参加
- containerd設定
- kubeadm joinでクラスタ参加

### Phase 3.3: CNI（Flannel）インストール
- Flannelマニフェスト適用
- Pod間通信の設定

### Phase 3.4: クラスタ状態確認
- Node状態確認
- Pod状態確認
- 接続情報の生成

## 構築後の確認

### Control Plane での確認

```bash
# Control Planeに接続
ssh k8suser@192.168.122.10

# クラスタ状態確認
kubectl get nodes -o wide
kubectl get pods --all-namespaces

# クラスタ情報確認
kubectl cluster-info
```

### 外部からの接続設定

```bash
# kubectl設定を外部に取得
scp k8suser@192.168.122.10:/home/k8suser/.kube/config ~/.kube/config-k8s-cluster

# 外部からクラスタ操作
export KUBECONFIG=~/.kube/config-k8s-cluster
kubectl get nodes
```

## 期待される結果

### 正常な構築完了時

```bash
$ kubectl get nodes -o wide
NAME                STATUS   ROLES           AGE   VERSION   INTERNAL-IP      EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
k8s-control-plane   Ready    control-plane   5m    v1.29.0   192.168.122.10   <none>        Ubuntu 22.04.5 LTS   5.15.0-XXX-generic   containerd://1.7.X
k8s-worker1         Ready    <none>          3m    v1.29.0   192.168.122.11   <none>        Ubuntu 22.04.5 LTS   5.15.0-XXX-generic   containerd://1.7.X
k8s-worker2         Ready    <none>          3m    v1.29.0   192.168.122.12   <none>        Ubuntu 22.04.5 LTS   5.15.0-XXX-generic   containerd://1.7.X

$ kubectl get pods --all-namespaces
NAMESPACE      NAME                                READY   STATUS    RESTARTS   AGE
kube-flannel   kube-flannel-ds-XXX                 1/1     Running   0          2m
kube-system    coredns-XXX                         1/1     Running   0          5m
kube-system    etcd-k8s-control-plane              1/1     Running   0          5m
kube-system    kube-apiserver-k8s-control-plane    1/1     Running   0          5m
kube-system    kube-controller-manager-XXX         1/1     Running   0          5m
kube-system    kube-proxy-XXX                      1/1     Running   0          5m
kube-system    kube-scheduler-k8s-control-plane    1/1     Running   0          5m
```

## 次のステップ

k8sクラスタ構築完了後は、Phase 4（基本インフラ）に進みます：

- MetalLB（LoadBalancer）
- Ingress Controller（NGINX）
- cert-manager
- NFS StorageClass

## トラブルシューティング

### 接続エラー

```bash
# SSH接続確認
ansible -i inventory.ini all -m ping

# cloud-init完了確認
ssh k8suser@192.168.122.10 'sudo cloud-init status --wait'
```

### kubeadm init失敗

```bash
# Control Planeでエラー確認
ssh k8suser@192.168.122.10 'sudo journalctl -u kubelet -f'

# kubeadm初期化リセット
ssh k8suser@192.168.122.10 'sudo kubeadm reset -f'
```

### Worker Node参加失敗

```bash
# Worker NodeでJoinコマンド確認
ssh k8suser@192.168.122.11 'cat /tmp/worker-join-command.sh'

# 手動でJoin実行
ssh k8suser@192.168.122.11 'sudo kubeadm reset -f && sudo bash /tmp/worker-join-command.sh'
```

### CNI（Flannel）問題

```bash
# Flannel Pod状態確認
kubectl get pods -n kube-flannel

# Flannel再適用
kubectl delete -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

## 手動構築（参考）

Ansibleを使わない場合の手動構築手順：

### Control Plane

```bash
ssh k8suser@192.168.122.10

# kubeadm init
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=192.168.122.10

# kubectl設定
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# CNI (Flannel) インストール
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

### Worker Nodes

```bash
# Control PlaneでJoinコマンド取得
kubeadm token create --print-join-command

# Worker Nodeで実行
ssh k8suser@192.168.122.11
sudo [join-command]

ssh k8suser@192.168.122.12  
sudo [join-command]
```