variable "external_storage_path" {
  description = "Path to external USB storage on the host"
  type        = string
  default     = "/mnt/external-ssd"
}

variable "nfs_server_ip" {
  description = "IP address of the NFS server (control plane IP)"
  type        = string
}