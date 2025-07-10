# Phase 2: VM構築用変数定義

variable "vm_user" {
  description = "VM内で使用するユーザー名"
  type        = string
  default     = "k8suser"
}

variable "ssh_public_key" {
  description = "VM接続用のSSH公開鍵"
  type        = string
  default     = ""
}

variable "control_plane_ip" {
  description = "Control PlaneのIPアドレス"
  type        = string
  default     = "192.168.122.10"
}

variable "worker1_ip" {
  description = "Worker Node 1のIPアドレス"
  type        = string
  default     = "192.168.122.11"
}

variable "worker2_ip" {
  description = "Worker Node 2のIPアドレス"
  type        = string
  default     = "192.168.122.12"
}

variable "network_gateway" {
  description = "ネットワークゲートウェイ"
  type        = string
  default     = "192.168.122.1"
}

variable "dns_servers" {
  description = "DNSサーバーのリスト"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "nfs_server_ip" {
  description = "NFSサーバー（ホストマシン）のIPアドレス"
  type        = string
  default     = "192.168.122.1"
}

# VM仕様設定
variable "control_plane_memory" {
  description = "Control PlaneのメモリサイズMB"
  type        = number
  default     = 8192  # 8GB
}

variable "control_plane_vcpu" {
  description = "Control PlaneのvCPU数"
  type        = number
  default     = 4
}

variable "control_plane_disk_size" {
  description = "Control Planeのディスクサイズ（バイト）"
  type        = number
  default     = 53687091200  # 50GB
}

variable "worker_memory" {
  description = "Worker NodeのメモリサイズMB"
  type        = number
  default     = 4096  # 4GB
}

variable "worker_vcpu" {
  description = "Worker NodeのvCPU数"
  type        = number
  default     = 2
}

variable "worker_disk_size" {
  description = "Worker Nodeのディスクサイズ（バイト）"
  type        = number
  default     = 32212254720  # 30GB
}