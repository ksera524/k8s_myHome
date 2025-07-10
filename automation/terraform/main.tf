# Phase 2: VM構築用Terraformコード
# Control Plane 1台 + Worker Node 2台のVM構築

terraform {
  required_version = ">= 1.0"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7.0"
    }
  }
}

# libvirt provider設定
provider "libvirt" {
  uri = "qemu:///system"
}

# Ubuntu 22.04 LTS Server イメージのダウンロード
resource "libvirt_volume" "ubuntu_base" {
  name   = "ubuntu-22.04-server-cloudimg-amd64.img"
  source = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  pool   = "default"
  format = "qcow2"
}

# Control Plane VM用ディスク
resource "libvirt_volume" "control_plane_disk" {
  name           = "k8s-control-plane-disk.qcow2"
  base_volume_id = libvirt_volume.ubuntu_base.id
  pool           = "default"
  size           = 53687091200  # 50GB
}

# Worker Node 1用ディスク
resource "libvirt_volume" "worker1_disk" {
  name           = "k8s-worker1-disk.qcow2"
  base_volume_id = libvirt_volume.ubuntu_base.id
  pool           = "default"
  size           = 32212254720  # 30GB
}

# Worker Node 2用ディスク
resource "libvirt_volume" "worker2_disk" {
  name           = "k8s-worker2-disk.qcow2"
  base_volume_id = libvirt_volume.ubuntu_base.id
  pool           = "default"
  size           = 32212254720  # 30GB
}

# ブリッジネットワーク（既存のdefaultネットワークを使用）
data "libvirt_network" "default" {
  name = "default"
}

# Control Plane VM用cloud-init設定
resource "libvirt_cloudinit_disk" "control_plane_init" {
  name = "k8s-control-plane-init.iso"
  pool = "default"

  user_data = templatefile("${path.module}/cloud-init/control-plane-user-data.yaml", {
    hostname = "k8s-control-plane"
    username = var.vm_user
    ssh_key  = var.ssh_public_key
  })

  network_config = templatefile("${path.module}/cloud-init/network-config.yaml", {
    ip_address = var.control_plane_ip
    gateway    = var.network_gateway
    dns_servers = var.dns_servers
  })
}

# Worker Node 1用cloud-init設定
resource "libvirt_cloudinit_disk" "worker1_init" {
  name = "k8s-worker1-init.iso"
  pool = "default"

  user_data = templatefile("${path.module}/cloud-init/worker-user-data.yaml", {
    hostname = "k8s-worker1"
    username = var.vm_user
    ssh_key  = var.ssh_public_key
  })

  network_config = templatefile("${path.module}/cloud-init/network-config.yaml", {
    ip_address = var.worker1_ip
    gateway    = var.network_gateway
    dns_servers = var.dns_servers
  })
}

# Worker Node 2用cloud-init設定
resource "libvirt_cloudinit_disk" "worker2_init" {
  name = "k8s-worker2-init.iso"
  pool = "default"

  user_data = templatefile("${path.module}/cloud-init/worker-user-data.yaml", {
    hostname = "k8s-worker2"
    username = var.vm_user
    ssh_key  = var.ssh_public_key
  })

  network_config = templatefile("${path.module}/cloud-init/network-config.yaml", {
    ip_address = var.worker2_ip
    gateway    = var.network_gateway
    dns_servers = var.dns_servers
  })
}

# Control Plane VM
resource "libvirt_domain" "control_plane" {
  name   = "k8s-control-plane"
  memory = 8192  # 8GB
  vcpu   = 4

  cloudinit = libvirt_cloudinit_disk.control_plane_init.id

  network_interface {
    network_id     = data.libvirt_network.default.id
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

  # 外部ストレージをマウントするためのディスク
  filesystem {
    source   = "/mnt/k8s-storage"
    target   = "k8s-storage"
    readonly = false
  }
}

# Worker Node 1 VM
resource "libvirt_domain" "worker1" {
  name   = "k8s-worker1"
  memory = 4096  # 4GB
  vcpu   = 2

  cloudinit = libvirt_cloudinit_disk.worker1_init.id

  network_interface {
    network_id     = data.libvirt_network.default.id
    wait_for_lease = true
    addresses      = [var.worker1_ip]
  }

  disk {
    volume_id = libvirt_volume.worker1_disk.id
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

  # 外部ストレージをマウントするためのディスク
  filesystem {
    source   = "/mnt/k8s-storage"
    target   = "k8s-storage"
    readonly = false
  }
}

# Worker Node 2 VM
resource "libvirt_domain" "worker2" {
  name   = "k8s-worker2"
  memory = 4096  # 4GB
  vcpu   = 2

  cloudinit = libvirt_cloudinit_disk.worker2_init.id

  network_interface {
    network_id     = data.libvirt_network.default.id
    wait_for_lease = true
    addresses      = [var.worker2_ip]
  }

  disk {
    volume_id = libvirt_volume.worker2_disk.id
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

  # 外部ストレージをマウントするためのディスク
  filesystem {
    source   = "/mnt/k8s-storage"
    target   = "k8s-storage"
    readonly = false
  }
}