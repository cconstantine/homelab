locals {
  local_storage_class = "local-storage"
  # homelab is the k3s node these volumes are pinned to and the machine
  # that physically owns /storage - these are plain local directories on
  # its own disk, not network mounts, so this is also where jellyfin and
  # every arr-stack app now run.
  config_node = "homelab"
  puid        = "1000"
  pgid        = "1000"
}

# Note: the "local-storage" StorageClass is already created by the
# monitoring module (kubernetes.io/no-provisioner, WaitForFirstConsumer).
# It's a cluster-scoped object, so it's reused by name here rather than
# declared again.

# Shared staging area: qbittorrent downloads here, radarr/sonarr import
# from here into the jellyfin media library below. Being local paths on
# the same underlying filesystem as movies/tv (not separate NFS mounts),
# hardlink-based imports work instead of falling back to a copy.
resource "kubernetes_persistent_volume" "downloads" {
  metadata {
    name = "arr-downloads"
    labels = {
      type = "local"
      app  = "arr"
      use  = "downloads"
    }
  }
  spec {
    capacity = {
      storage = "500Gi"
    }
    access_modes                     = ["ReadWriteOnce"]
    storage_class_name               = local.local_storage_class
    persistent_volume_reclaim_policy = "Retain"
    persistent_volume_source {
      local {
        path = "/storage/arr/downloads"
      }
    }
    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "kubernetes.io/hostname"
            operator = "In"
            values   = [local.config_node]
          }
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "downloads" {
  wait_until_bound = false
  metadata {
    name      = "arr-downloads"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = local.local_storage_class
    resources {
      requests = {
        storage = "500Gi"
      }
    }
    selector {
      match_labels = {
        type = "local"
        app  = "arr"
        use  = "downloads"
      }
    }
  }
}

# Same underlying directory the jellyfin module mounts at /media/movies.
# A separate PV/PVC pair is required here since a PV can only be Bound to
# one PVC at a time, but both apps run on homelab now so a local volume is
# happy to be mounted from both.
resource "kubernetes_persistent_volume" "movies" {
  metadata {
    name = "arr-movies"
    labels = {
      type = "local"
      app  = "arr"
      use  = "movies"
    }
  }
  spec {
    capacity = {
      storage = "1Ti"
    }
    access_modes                     = ["ReadWriteOnce"]
    storage_class_name               = local.local_storage_class
    persistent_volume_reclaim_policy = "Retain"
    persistent_volume_source {
      local {
        path = "/storage/jellyfin/media/movies"
      }
    }
    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "kubernetes.io/hostname"
            operator = "In"
            values   = [local.config_node]
          }
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "movies" {
  wait_until_bound = false
  metadata {
    name      = "arr-movies"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = local.local_storage_class
    resources {
      requests = {
        storage = "1Ti"
      }
    }
    selector {
      match_labels = {
        type = "local"
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
      type = "local"
      app  = "arr"
      use  = "tv"
    }
  }
  spec {
    capacity = {
      storage = "1Ti"
    }
    access_modes                     = ["ReadWriteOnce"]
    storage_class_name               = local.local_storage_class
    persistent_volume_reclaim_policy = "Retain"
    persistent_volume_source {
      local {
        path = "/storage/jellyfin/media/tv"
      }
    }
    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "kubernetes.io/hostname"
            operator = "In"
            values   = [local.config_node]
          }
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "tv" {
  wait_until_bound = false
  metadata {
    name      = "arr-tv"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = local.local_storage_class
    resources {
      requests = {
        storage = "1Ti"
      }
    }
    selector {
      match_labels = {
        type = "local"
        app  = "arr"
        use  = "tv"
      }
    }
  }
}
