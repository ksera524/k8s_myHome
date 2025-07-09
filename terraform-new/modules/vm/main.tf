# VM Infrastructure Module
terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.1"
    }
  }
}

# Create Ubuntu cloud image
resource "libvirt_volume" "ubuntu_base" {
  name   = "ubuntu-22.04-base"
  pool   = "default"
  source = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  format = "qcow2"
}

# Control Plane VM volumes
resource "libvirt_volume" "control_plane" {
  count          = var.control_plane_count
  name           = "k8s-control-plane-${count.index + 1}"
  pool           = "default"
  base_volume_id = libvirt_volume.ubuntu_base.id
  size           = 107374182400  # 100GB
}

# Worker Node VM volumes
resource "libvirt_volume" "worker_node" {
  count          = var.worker_node_count
  name           = "k8s-worker-${count.index + 1}"
  pool           = "default"
  base_volume_id = libvirt_volume.ubuntu_base.id
  size           = 107374182400  # 100GB
}

# Cloud-init for Control Plane
data "template_file" "control_plane_cloud_init" {
  count = var.control_plane_count
  template = file("${path.module}/cloud-init-control-plane.yml")
  vars = {
    hostname = "k8s-control-plane-${count.index + 1}"
    ssh_key  = file("~/.ssh/id_rsa.pub")
  }
}

# Cloud-init for Worker Nodes
data "template_file" "worker_node_cloud_init" {
  count = var.worker_node_count
  template = file("${path.module}/cloud-init-worker.yml")
  vars = {
    hostname = "k8s-worker-${count.index + 1}"
    ssh_key  = file("~/.ssh/id_rsa.pub")
  }
}

# Cloud-init ISOs for Control Plane
resource "libvirt_cloudinit_disk" "control_plane_init" {
  count     = var.control_plane_count
  name      = "k8s-control-plane-${count.index + 1}-init"
  pool      = "default"
  user_data = data.template_file.control_plane_cloud_init[count.index].rendered
}

# Cloud-init ISOs for Worker Nodes
resource "libvirt_cloudinit_disk" "worker_node_init" {
  count     = var.worker_node_count
  name      = "k8s-worker-${count.index + 1}-init"
  pool      = "default"
  user_data = data.template_file.worker_node_cloud_init[count.index].rendered
}

# Control Plane VMs
resource "libvirt_domain" "control_plane" {
  count  = var.control_plane_count
  name   = "k8s-control-plane-${count.index + 1}"
  memory = var.vm_memory
  vcpu   = var.vm_vcpu

  cloudinit = libvirt_cloudinit_disk.control_plane_init[count.index].id

  network_interface {
    network_name   = "default"
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.control_plane[count.index].id
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
resource "libvirt_domain" "worker_node" {
  count  = var.worker_node_count
  name   = "k8s-worker-${count.index + 1}"
  memory = var.vm_memory
  vcpu   = var.vm_vcpu

  cloudinit = libvirt_cloudinit_disk.worker_node_init[count.index].id

  network_interface {
    network_name   = "default"
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.worker_node[count.index].id
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