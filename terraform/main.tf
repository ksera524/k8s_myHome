# Configure the Kubernetes provider
terraform {
  required_providers {
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

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "default"
}

variable "localhost" {
  type        = string
  default     = "192.168.10.11"
}

# Create a namespace
resource "kubernetes_namespace" "namespaces" {
  for_each = toset(["sandbox", "argocd", "cloudflared", "harbor","cert-manager","argoworkflow"])
  
  metadata {
    name = each.key
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
    namespace = kubernetes_namespace.namespaces["harbor"].metadata[0].name
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

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "default"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.namespaces["argocd"].metadata[0].name

  set {
    name  = "server.service.type"
    value = "NodePort"
  }

  timeout = 600 
}

resource "helm_release" "argoworkflow" {
  name       = "argo-workflow"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-workflows"
  namespace  = kubernetes_namespace.namespaces["argoworkflow"].metadata[0].name

  set {
    name  = "server.serviceType"
    value = "NodePort"
  }

  set {
    name  = "server.serviceNodePort"
    value = "30001"
  }
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = kubernetes_namespace.namespaces["cert-manager"].metadata[0].name

  set {
    name  = "installCRDs"
    value = "true"
  }
}

resource "helm_release" "harbor" {
  name       = "harbor"
  repository = "https://helm.goharbor.io"
  chart      = "harbor"
  namespace  = "harbor"

  set {
    name  = "externalURL"
    value = "https://${var.localhost}:30003"
  }

  set {
    name  = "expose.type"
    value = "nodePort"
  }

  set {
    name  = "expose.tls.enabled"
    value = "true"
  }

  set {
    name  = "expose.tls.auto.commonName"
    value = "${var.localhost}"
  }

  set {
    name  = "expose.tls.secretName"
    value = "harbor-tls"
  }

  set {
    name  = "persistence.database.existingClaim"
    value = "external-ssd-pvc"
  }

  set {
    name  = "persistence.database.size"
    value = "10Gi"
  }

  set {
    name  = "persistence.database.storageClass"
    value = "manual"
  }

  set {
    name  = "persistence.database.subPath"
    value = "harbor-database"
  }

  set {
    name  = "persistence.jobservice.existingClaim"
    value = "external-ssd-pvc"
  }

  set {
    name  = "persistence.jobservice.size"
    value = "10Gi"
  }

  set {
    name  = "persistence.jobservice.storageClass"
    value = "manual"
  }

  set {
    name  = "persistence.jobservice.subPath"
    value = "harbor-jobservice"
  }

  set {
    name  = "persistence.redis.existingClaim"
    value = "external-ssd-pvc"
  }

  set {
    name  = "persistence.redis.size"
    value = "10Gi"
  }

  set {
    name  = "persistence.redis.storageClass"
    value = "manual"
  }

  set {
    name  = "persistence.redis.subPath"
    value = "harbor-redis"
  }

  set {
    name  = "persistence.registry.existingClaim"
    value = "external-ssd-pvc"
  }

  set {
    name  = "persistence.registry.size"
    value = "100Gi"
  }

  set {
    name  = "persistence.registry.storageClass"
    value = "manual"
  }

  set {
    name  = "persistence.registry.subPath"
    value = "harbor-registry"
  }

  set {
    name  = "persistence.resourcePolicy"
    value = "delete"
  }

    set {
    name  = "trivy.enabled"
    value = "false"
  }
}