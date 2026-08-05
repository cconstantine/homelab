locals {
  nfs_server          = "homelab.local"
  nfs_storage_class   = "nfs-storage"
  local_storage_class = "local-storage"
  # homelab is both the k3s node these config PVs are pinned to and the
  # machine serving /storage over NFS, so this path is the same directory
  # the nfs-storage PVs used to point at - no data migration needed.
  config_node = "homelab"
  puid        = "1000"
  pgid        = "1000"
}

# Note: the "nfs-storage" StorageClass is already created by the frigate
# module (kubernetes.io/no-provisioner, Retain). It's a cluster-scoped
# object, so it's reused by name here rather than declared again.

# Shared staging area: qbittorrent downloads here, radarr/sonarr import
# from here into the jellyfin media library below.
resource "kubernetes_persistent_volume" "downloads" {
  metadata {
    name = "arr-downloads"
    labels = {
      type = "nfs"
      app  = "arr"
      use  = "downloads"
    }
  }
  spec {
    capacity = {
      storage = "500Gi"
    }
    access_modes       = ["ReadWriteMany"]
    storage_class_name = local.nfs_storage_class
    persistent_volume_source {
      nfs {
        server = local.nfs_server
        path   = "/storage/arr/downloads"
      }
    }
    persistent_volume_reclaim_policy = "Retain"
  }
}

resource "kubernetes_persistent_volume_claim" "downloads" {
  metadata {
    name      = "arr-downloads"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = local.nfs_storage_class
    resources {
      requests = {
        storage = "500Gi"
      }
    }
    selector {
      match_labels = {
        type = "nfs"
        app  = "arr"
        use  = "downloads"
      }
    }
  }
}

# Same underlying NFS export the jellyfin module mounts at /media/movies.
# A separate PV/PVC pair is required here since a PV can only be Bound to
# one PVC at a time, but NFS itself is happy to be mounted from both.
resource "kubernetes_persistent_volume" "movies" {
  metadata {
    name = "arr-movies"
    labels = {
      type = "nfs"
      app  = "arr"
      use  = "movies"
    }
  }
  spec {
    capacity = {
      storage = "1Ti"
    }
    access_modes       = ["ReadWriteMany"]
    storage_class_name = local.nfs_storage_class
    persistent_volume_source {
      nfs {
        server = local.nfs_server
        path   = "/storage/jellyfin/media/movies"
      }
    }
    persistent_volume_reclaim_policy = "Retain"
  }
}

resource "kubernetes_persistent_volume_claim" "movies" {
  metadata {
    name      = "arr-movies"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = local.nfs_storage_class
    resources {
      requests = {
        storage = "1Ti"
      }
    }
    selector {
      match_labels = {
        type = "nfs"
        app  = "arr"
        use  = "movies"
      }
    }
  }
}

resource "kubernetes_persistent_volume" "tv" {
  metadata {
    name = "arr-tv"
    labels = {
      type = "nfs"
      app  = "arr"
      use  = "tv"
    }
  }
  spec {
    capacity = {
      storage = "1Ti"
    }
    access_modes       = ["ReadWriteMany"]
    storage_class_name = local.nfs_storage_class
    persistent_volume_source {
      nfs {
        server = local.nfs_server
        path   = "/storage/jellyfin/media/tv"
      }
    }
    persistent_volume_reclaim_policy = "Retain"
  }
}

resource "kubernetes_persistent_volume_claim" "tv" {
  metadata {
    name      = "arr-tv"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = local.nfs_storage_class
    resources {
      requests = {
        storage = "1Ti"
      }
    }
    selector {
      match_labels = {
        type = "nfs"
        app  = "arr"
        use  = "tv"
      }
    }
  }
}
