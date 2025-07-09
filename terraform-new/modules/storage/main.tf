# Storage Integration Module
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

# NFS Server Service
resource "kubernetes_service" "nfs_server" {
  metadata {
    name      = "nfs-server"
    namespace = "kube-system"
    labels = {
      app = "nfs-server"
    }
  }

  spec {
    selector = {
      app = "nfs-server"
    }

    port {
      name        = "nfs"
      port        = 2049
      target_port = 2049
      protocol    = "TCP"
    }

    port {
      name        = "mountd"
      port        = 20048
      target_port = 20048
      protocol    = "TCP"
    }

    port {
      name        = "rpcbind"
      port        = 111
      target_port = 111
      protocol    = "TCP"
    }
  }
}

# NFS Server Deployment
resource "kubernetes_deployment" "nfs_server" {
  metadata {
    name      = "nfs-server"
    namespace = "kube-system"
    labels = {
      app = "nfs-server"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "nfs-server"
      }
    }

    template {
      metadata {
        labels = {
          app = "nfs-server"
        }
      }

      spec {
        node_selector = {
          "kubernetes.io/hostname" = "k8s-control-plane-1"
        }

        container {
          name  = "nfs-server"
          image = "itsthenetwork/nfs-server-alpine:latest"

          port {
            name           = "nfs"
            container_port = 2049
          }

          port {
            name           = "mountd"
            container_port = 20048
          }

          port {
            name           = "rpcbind"
            container_port = 111
          }

          security_context {
            privileged = true
          }

          volume_mount {
            name       = "external-storage"
            mount_path = "/exports"
          }

          env {
            name  = "SHARED_DIRECTORY"
            value = "/exports"
          }
        }

        volume {
          name = "external-storage"
          host_path {
            path = var.external_storage_path
            type = "Directory"
          }
        }
      }
    }
  }
}

# Install NFS CSI Driver via Helm
resource "helm_release" "nfs_csi_driver" {
  name       = "csi-driver-nfs"
  repository = "https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts"
  chart      = "csi-driver-nfs"
  namespace  = "kube-system"

  set {
    name  = "kubeletDir"
    value = "/var/lib/kubelet"
  }
}

# NFS StorageClass
resource "kubernetes_storage_class" "nfs_external" {
  depends_on = [helm_release.nfs_csi_driver]

  metadata {
    name = "nfs-external"
  }

  storage_provisioner    = "nfs.csi.k8s.io"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "Immediate"
  allow_volume_expansion = true

  parameters = {
    server = var.nfs_server_ip
    share  = "/exports"
    mountPermissions = "0755"
  }
}

# Default StorageClass for local storage
resource "kubernetes_storage_class" "local_storage" {
  metadata {
    name = "local-storage"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner = "kubernetes.io/no-provisioner"
  volume_binding_mode = "WaitForFirstConsumer"
}