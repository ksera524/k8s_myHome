# Phase 2: 改善されたVM構築用Terraformコード
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
    wait_for_lease = true
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
    wait_for_lease = true
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