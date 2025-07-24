# Phase 2&3統合: VM構築+Kubernetesクラスター構築用Terraformコード
# ランダムIDを使用してリソース重複を回避

terraform {
  required_version = ">= 1.0"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.1"
    }
  }
}

# ランダムIDでユニークなリソース名を生成
resource "random_id" "cluster" {
  byte_length = 4
}

# libvirt provider設定
provider "libvirt" {
  uri = "qemu:///system"
}

# Ubuntu 22.04 LTS Server イメージ
resource "libvirt_volume" "ubuntu_base" {
  name   = "ubuntu-base-${random_id.cluster.hex}.img"
  source = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  pool   = "default"
  format = "qcow2"
}

# Control Plane VM用ディスク
resource "libvirt_volume" "control_plane_disk" {
  name           = "k8s-control-plane-${random_id.cluster.hex}.qcow2"
  base_volume_id = libvirt_volume.ubuntu_base.id
  pool           = "default"
  size           = 53687091200  # 50GB
}

# Worker Node ディスク
resource "libvirt_volume" "worker_disk" {
  count          = 2
  name           = "k8s-worker${count.index + 1}-${random_id.cluster.hex}.qcow2"
  base_volume_id = libvirt_volume.ubuntu_base.id
  pool           = "default"
  size           = 32212254720  # 30GB
}

# 簡素化されたcloud-init設定
data "template_file" "user_data" {
  count = 3
  template = file("${path.module}/cloud-init/user-data.yaml")
  vars = {
    vm_hostname = count.index == 0 ? "k8s-control-plane" : "k8s-worker${count.index}"
    username = var.vm_user
    ssh_key  = var.ssh_public_key
  }
}

data "template_file" "network_config" {
  count = 3
  template = file("${path.module}/cloud-init/network-config.yaml")
  vars = {
    ip_address = count.index == 0 ? var.control_plane_ip : var.worker_ips[count.index - 1]
    gateway    = var.network_gateway
  }
}

# Control Plane cloud-init
resource "libvirt_cloudinit_disk" "control_plane_init" {
  name           = "k8s-control-plane-init-${random_id.cluster.hex}.iso"
  pool           = "default"
  user_data      = data.template_file.user_data.0.rendered
  network_config = data.template_file.network_config.0.rendered
}

# Worker Node cloud-init
resource "libvirt_cloudinit_disk" "worker_init" {
  count          = 2
  name           = "k8s-worker${count.index + 1}-init-${random_id.cluster.hex}.iso"
  pool           = "default"
  user_data      = data.template_file.user_data[count.index + 1].rendered
  network_config = data.template_file.network_config[count.index + 1].rendered
}

# Control Plane VM
resource "libvirt_domain" "control_plane" {
  name   = "k8s-control-plane-${random_id.cluster.hex}"
  memory = var.control_plane_memory
  vcpu   = var.control_plane_vcpu

  cloudinit = libvirt_cloudinit_disk.control_plane_init.id

  network_interface {
    network_name   = "default"
    wait_for_lease = false
    addresses      = [var.control_plane_ip]
  }

  disk {
    volume_id = libvirt_volume.control_plane_disk.id
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
}

# Worker Node VMs
resource "libvirt_domain" "worker" {
  count  = 2
  name   = "k8s-worker${count.index + 1}-${random_id.cluster.hex}"
  memory = var.worker_memory
  vcpu   = var.worker_vcpu

  cloudinit = libvirt_cloudinit_disk.worker_init[count.index].id

  network_interface {
    network_name   = "default"
    wait_for_lease = false
    addresses      = [var.worker_ips[count.index]]
  }

  disk {
    volume_id = libvirt_volume.worker_disk[count.index].id
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
}

# VMの起動完了を待つためのリソース
resource "null_resource" "wait_for_vms" {
  depends_on = [
    libvirt_domain.control_plane,
    libvirt_domain.worker
  ]

  provisioner "local-exec" {
    command = "sleep 60"  # VMの起動とcloud-init完了を待つ
  }
}

# Kubernetes環境セットアップ（Control Plane）
resource "null_resource" "k8s_control_plane_setup" {
  depends_on = [null_resource.wait_for_vms]
  
  connection {
    type        = "ssh"
    host        = var.control_plane_ip
    user        = var.vm_user
    private_key = file(var.ssh_private_key_path)
  }
  
  # cloud-init完了を待機
  provisioner "remote-exec" {
    inline = [
      "timeout 300 bash -c 'until [ -f /var/log/cloud-init-complete ]; do sleep 5; done'"
    ]
  }
  
  # Kubernetesパッケージインストール
  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
      "sudo apt install -y apt-transport-https ca-certificates curl gpg containerd",
      "curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg",
      "echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list",
      "sudo apt update",
      "sudo apt install -y kubelet=1.29.0-1.1 kubeadm=1.29.0-1.1 kubectl=1.29.0-1.1",
      "sudo apt-mark hold kubelet kubeadm kubectl"
    ]
  }
  
  # カーネルモジュールとネットワーク設定
  provisioner "remote-exec" {
    inline = [
      "sudo modprobe br_netfilter",
      "sudo modprobe overlay",
      "echo 'br_netfilter' | sudo tee /etc/modules-load.d/k8s.conf",
      "echo 'overlay' | sudo tee -a /etc/modules-load.d/k8s.conf",
      "echo 'net.bridge.bridge-nf-call-iptables = 1' | sudo tee /etc/sysctl.d/k8s.conf",
      "echo 'net.bridge.bridge-nf-call-ip6tables = 1' | sudo tee -a /etc/sysctl.d/k8s.conf",
      "echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/k8s.conf",
      "sudo sysctl --system"
    ]
  }
  
  # containerd設定
  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /etc/containerd",
      "sudo containerd config default | sudo tee /etc/containerd/config.toml",
      "sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml",
      "sudo systemctl restart containerd",
      "sudo systemctl enable containerd"
    ]
  }
  
  # kubeadm設定ファイル作成
  provisioner "remote-exec" {
    inline = [
      <<-EOF
        sudo tee /tmp/kubeadm-config.yaml > /dev/null <<EOL
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: ${var.control_plane_ip}
  bindPort: 6443
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: ${var.kubernetes_version}
controlPlaneEndpoint: "${var.control_plane_ip}:6443"
networking:
  podSubnet: "${var.pod_network_cidr}"
  serviceSubnet: "${var.service_network_cidr}"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOL
      EOF
    ]
  }
  
  # kubeadmクラスター初期化
  provisioner "remote-exec" {
    inline = [
      "sudo kubeadm init --config=/tmp/kubeadm-config.yaml --upload-certs",
      "mkdir -p /home/${var.vm_user}/.kube",
      "sudo cp -i /etc/kubernetes/admin.conf /home/${var.vm_user}/.kube/config",
      "sudo chown ${var.vm_user}:${var.vm_user} /home/${var.vm_user}/.kube/config",
      "kubeadm token create --print-join-command > /tmp/worker-join-command.txt"
    ]
  }
  
  # Harbor用ストレージディレクトリ作成
  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /tmp/harbor-registry /tmp/harbor-database /tmp/harbor-redis /tmp/harbor-trivy /tmp/harbor-jobservice",
      "sudo chmod 777 /tmp/harbor-*"
    ]
  }
}

# Worker Nodeセットアップ
resource "null_resource" "k8s_worker_setup" {
  count = length(var.worker_ips)
  depends_on = [null_resource.k8s_control_plane_setup]
  
  connection {
    type        = "ssh"
    host        = var.worker_ips[count.index]
    user        = var.vm_user
    private_key = file(var.ssh_private_key_path)
  }
  
  # cloud-init完了を待機
  provisioner "remote-exec" {
    inline = [
      "timeout 300 bash -c 'until [ -f /var/log/cloud-init-complete ]; do sleep 5; done'"
    ]
  }
  
  # Kubernetesパッケージインストール
  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
      "sudo apt install -y apt-transport-https ca-certificates curl gpg containerd",
      "curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg",
      "echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list",
      "sudo apt update",
      "sudo apt install -y kubelet=1.29.0-1.1 kubeadm=1.29.0-1.1 kubectl=1.29.0-1.1",
      "sudo apt-mark hold kubelet kubeadm kubectl"
    ]
  }
  
  # カーネルモジュールとネットワーク設定
  provisioner "remote-exec" {
    inline = [
      "sudo modprobe br_netfilter",
      "sudo modprobe overlay",
      "echo 'br_netfilter' | sudo tee /etc/modules-load.d/k8s.conf",
      "echo 'overlay' | sudo tee -a /etc/modules-load.d/k8s.conf",
      "echo 'net.bridge.bridge-nf-call-iptables = 1' | sudo tee /etc/sysctl.d/k8s.conf",
      "echo 'net.bridge.bridge-nf-call-ip6tables = 1' | sudo tee -a /etc/sysctl.d/k8s.conf",
      "echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/k8s.conf",
      "sudo sysctl --system"
    ]
  }
  
  # containerd設定
  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /etc/containerd",
      "sudo containerd config default | sudo tee /etc/containerd/config.toml",
      "sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml",
      "sudo systemctl restart containerd",
      "sudo systemctl enable containerd"
    ]
  }
  
  # Harbor用ストレージディレクトリ作成
  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /tmp/harbor-registry /tmp/harbor-database /tmp/harbor-redis /tmp/harbor-trivy /tmp/harbor-jobservice",
      "sudo chmod 777 /tmp/harbor-*"
    ]
  }
}

# joinコマンドを取得してWorker Nodeに配布
resource "null_resource" "worker_join" {
  count = length(var.worker_ips)
  depends_on = [null_resource.k8s_worker_setup]
  
  # joinコマンドをControl Planeから取得してローカルに保存
  provisioner "local-exec" {
    command = "ssh -o StrictHostKeyChecking=no -i ${var.ssh_private_key_path} ${var.vm_user}@${var.control_plane_ip} 'cat /tmp/worker-join-command.txt' > /tmp/worker-join-command.sh && chmod +x /tmp/worker-join-command.sh"
  }
  
  # joinコマンドをWorker Nodeにコピー
  provisioner "file" {
    connection {
      type        = "ssh"
      host        = var.worker_ips[count.index]
      user        = var.vm_user
      private_key = file(var.ssh_private_key_path)
    }
    
    source      = "/tmp/worker-join-command.sh"
    destination = "/tmp/worker-join-command.sh"
  }
  
  # Worker Nodeでjoin実行
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = var.worker_ips[count.index]
      user        = var.vm_user
      private_key = file(var.ssh_private_key_path)
    }
    
    inline = [
      "chmod +x /tmp/worker-join-command.sh",
      "sudo bash /tmp/worker-join-command.sh"
    ]
  }
}

# FlannelCNI インストール
resource "null_resource" "flannel_install" {
  depends_on = [null_resource.worker_join]
  
  connection {
    type        = "ssh"
    host        = var.control_plane_ip
    user        = var.vm_user
    private_key = file(var.ssh_private_key_path)
  }
  
  provisioner "remote-exec" {
    inline = [
      "timeout 300 bash -c 'until kubectl get nodes; do sleep 10; done'",
      "kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml",
      "sleep 30",
      "echo '=== Cluster Info ===' > /tmp/k8s-cluster-info.txt",
      "kubectl get nodes -o wide >> /tmp/k8s-cluster-info.txt",
      "echo '' >> /tmp/k8s-cluster-info.txt",
      "kubectl get pods --all-namespaces >> /tmp/k8s-cluster-info.txt"
    ]
  }
}