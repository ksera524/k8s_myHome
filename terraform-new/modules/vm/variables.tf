variable "control_plane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 1
}

variable "worker_node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "vm_memory" {
  description = "Memory allocation for VMs in MB"
  type        = number
  default     = 8192
}

variable "vm_vcpu" {
  description = "Number of vCPUs for VMs"
  type        = number
  default     = 4
}