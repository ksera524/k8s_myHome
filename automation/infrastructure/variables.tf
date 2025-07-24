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

# Kubernetesクラスター設定
variable "kubernetes_version" {
  description = "Kubernetesバージョン"
  type        = string
  default     = "v1.33.0"
}

variable "pod_network_cidr" {
  description = "Pod ネットワークCIDR（Flannel用）"
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_network_cidr" {
  description = "Service ネットワークCIDR"
  type        = string
  default     = "10.96.0.0/12"
}

variable "ssh_private_key_path" {
  description = "SSH秘密鍵のパス"
  type        = string
  default     = "~/.ssh/id_rsa"
}