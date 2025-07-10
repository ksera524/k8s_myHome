# Phase 2: VM構築用出力値定義

output "control_plane_ip" {
  description = "Control PlaneのIPアドレス"
  value       = var.control_plane_ip
}

output "worker1_ip" {
  description = "Worker Node 1のIPアドレス"
  value       = var.worker1_ip
}

output "worker2_ip" {
  description = "Worker Node 2のIPアドレス"
  value       = var.worker2_ip
}

output "vm_user" {
  description = "VM内のユーザー名"
  value       = var.vm_user
}

output "ssh_connection_commands" {
  description = "VM接続用SSHコマンド"
  value = {
    control_plane = "ssh ${var.vm_user}@${var.control_plane_ip}"
    worker1       = "ssh ${var.vm_user}@${var.worker1_ip}"
    worker2       = "ssh ${var.vm_user}@${var.worker2_ip}"
  }
}

output "vm_status" {
  description = "VM作成ステータス"
  value = {
    control_plane = libvirt_domain.control_plane.name
    worker1       = libvirt_domain.worker1.name
    worker2       = libvirt_domain.worker2.name
  }
}

output "ansible_inventory" {
  description = "Ansible用インベントリ情報"
  value = {
    control_plane = {
      host = var.control_plane_ip
      user = var.vm_user
    }
    workers = [
      {
        name = "worker1"
        host = var.worker1_ip
        user = var.vm_user
      },
      {
        name = "worker2"
        host = var.worker2_ip
        user = var.vm_user
      }
    ]
  }
}