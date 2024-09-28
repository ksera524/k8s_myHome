# Configure the Kubernetes provider
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "minikube"
}

# Create a namespace
resource "kubernetes_namespace" "sandbox" {
  metadata {
    name = "sandbox"
  }
}

# Define the Persistent Volume
resource "kubernetes_persistent_volume" "external_ssd_pv" {
  metadata {
    name = "external-ssd-pv"
  }

  spec {
    capacity = {
      storage = "3.4Ti"
    }

    access_modes = ["ReadWriteOnce"]

    persistent_volume_reclaim_policy = "Retain"

    storage_class_name = "manual"

    # This is the correct block structure
    persistent_volume_source {
      host_path {
        path = "/mnt/external-ssd"
      }
    }
  }
}

# Define a Persistent Volume Claim
resource "kubernetes_persistent_volume_claim" "external_ssd_pvc" {
  metadata {
    name      = "external-ssd-pvc"
    namespace = kubernetes_namespace.sandbox.metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "3.4Ti"
      }
    }

    storage_class_name = "manual"
  }
}
