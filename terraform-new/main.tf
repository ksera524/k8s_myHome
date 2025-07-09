# Main Terraform configuration for Kubernetes cluster migration
terraform {
  required_version = ">= 1.0"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0.0"
    }
  }
}

# Provider configurations
provider "libvirt" {
  uri = "qemu:///system"
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

# Variables
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

variable "external_storage_path" {
  description = "Path to external USB storage"
  type        = string
  default     = "/mnt/external-ssd"
}

# VM Infrastructure Module
module "vm_infrastructure" {
  source = "./modules/vm"
  
  control_plane_count = var.control_plane_count
  worker_node_count   = var.worker_node_count
  vm_memory          = var.vm_memory
  vm_vcpu            = var.vm_vcpu
}

# Kubernetes Cluster Module
module "kubernetes_cluster" {
  source = "./modules/k8s"
  
  depends_on = [module.vm_infrastructure]
  
  cluster_name = "k8s-home"
  pod_cidr     = "10.244.0.0/16"
  service_cidr = "10.96.0.0/12"
}

# Storage Integration Module
module "storage_integration" {
  source = "./modules/storage"
  
  depends_on = [module.kubernetes_cluster]
  
  external_storage_path = var.external_storage_path
  nfs_server_ip        = module.vm_infrastructure.control_plane_ip
}

# Outputs
output "control_plane_ip" {
  value = module.vm_infrastructure.control_plane_ip
}

output "worker_node_ips" {
  value = module.vm_infrastructure.worker_node_ips
}

output "kubeconfig_path" {
  value = "~/.kube/config"
}