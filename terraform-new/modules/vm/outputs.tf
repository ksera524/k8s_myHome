output "control_plane_ip" {
  description = "IP address of the control plane node"
  value       = libvirt_domain.control_plane[0].network_interface[0].addresses[0]
}

output "worker_node_ips" {
  description = "IP addresses of worker nodes"
  value       = [for node in libvirt_domain.worker_node : node.network_interface[0].addresses[0]]
}

output "control_plane_names" {
  description = "Names of control plane VMs"
  value       = libvirt_domain.control_plane[*].name
}

output "worker_node_names" {
  description = "Names of worker node VMs"
  value       = libvirt_domain.worker_node[*].name
}