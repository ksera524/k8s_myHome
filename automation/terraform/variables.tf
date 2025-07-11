# Phase 2: 改善された変数定義

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

variable "worker_ips" {
  description = "Worker NodeのIPアドレスリスト"
  type        = list(string)
  default     = ["192.168.122.11", "192.168.122.12"]
}

variable "network_gateway" {
  description = "ネットワークゲートウェイ"
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