provider "k3d" {
    version = "3.0.0"
}

# クラスタの作成
resource "k3d_cluster" "k3d" {
    name = "k3d"
    api_port = 6443
    ports = [8080]
    servers = 1
    agents = 1
}

# namespaceの作成
resource "kubernetes_namespace" "sandbox" {
    metadata {
        name = "sandbox"
    }
}

#外部SSD
resource "kubernetes_persistent_volume" "ssd_pv" {
    metadata {
        name = "ssd-pv"
    }

    spec {
        capacity {
            storage = "1Ti"
        }
        access_modes = ["ReadWriteOnce"]
        persistent_volume_reclaim_policy = "Retain"
        host_path {
            path = "/tmp"
        }
    }
}

resource "kubernetes_persistent_volume_claim" "ssd_pvc" {
    metadata {
        name = "ssd-pvc"
    }

    spec {
        access_modes = ["ReadWriteOnce"]
        resources {
            requests {
                storage = "1Ti"
            }
        }
    }
}

