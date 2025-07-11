# Phase 2: 出力値定義

output "cluster_id" {
  description = "クラスターの一意ID"
  value       = random_id.cluster.hex
}

output "control_plane_ip" {
  description = "Control PlaneのIPアドレス"
  value       = var.control_plane_ip
}

output "worker_ips" {
  description = "Worker NodeのIPアドレス一覧"
  value       = var.worker_ips
}

output "ssh_connection_commands" {
  description = "VM接続用SSHコマンド"
  value = {
    control_plane = "ssh ${var.vm_user}@${var.control_plane_ip}"
    worker1       = "ssh ${var.vm_user}@${var.worker_ips[0]}"
    worker2       = "ssh ${var.vm_user}@${var.worker_ips[1]}"
  }
}

output "vm_names" {
  description = "作成されたVM名"
  value = {
    control_plane = libvirt_domain.control_plane.name
    workers       = libvirt_domain.worker[*].name
  }
}