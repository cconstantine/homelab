locals {
  runner_node_arch = {
    amd64 = "amd64"
    arm64 = "arm64"
    armv7 = "arm64"
  }

  runner_targets = merge(
    { for p in var.runner_platforms : p => {
      github_config_url    = "https://github.com/twinkle-astronomy/srvr"
      github_config_secret = "arc-github-pat"
      platform             = p
      host_storage         = null
      dind_resources       = null
      min_runners          = 1
      max_runners          = 1
    } },
    # One runner per smelt CI job, so the jobs run side by side and each
    # keeps a cache of its own; ci.yml names them. Docker storage and the CI
    # build cache (see ci_cache_path) are on the node's own disk rather than
    # local-path PVCs: those live on homelab's SATA SSD with the rest of k3s,
    # which smelt's tests kept 95-100% busy. This path is on the node's root
    # disk, and every runner needs its own: two dockerds can't share one.
    #
    # A runner may land on any of `nodes`; each keeps its own copy of the
    # cache at the same path, so a run builds on whatever that node's last
    # run left (a node's first run starts cold). Not shared over the
    # network: target/ is 20-60GB of small files cargo stats, and Docker's
    # storage can't live on NFS -- whose only server here is homelab anyway.
    #
    # dind_resources reserve what a job's containers (the cargo build,
    # Postgres, a nested k3s) use, which run in the dind container's cgroup
    # (see nested_dockerd). Measured over one warm-cache run of both jobs:
    # server peaked at 11.1GiB and 5.9 cores (4.8 p95), browser at 9.5GiB and
    # 4.8 cores (3.4 p95), memory including reclaimable page cache. No CPU
    # limit: a cold build uses every idle core.
    #
    # Runners exist only while jobs run (min 0), so the reservations are
    # held only then; a job waits about a minute for its pod. Up to two per
    # job, one per node of host_storage.nodes (podAntiAffinity below): two
    # dockerds can't share a node's cache directory.
    { for name, r in {
      "smelt-amd64" = {
        dir = "/var/lib/arc-runner-smelt"
        resources = {
          requests = { cpu = "4", memory = "10Gi" }
          limits   = { memory = "16Gi" }
        }
      }
      "smelt-amd64-browser" = {
        dir = "/var/lib/arc-runner-smelt-browser"
        resources = {
          requests = { cpu = "3", memory = "8Gi" }
          limits   = { memory = "14Gi" }
        }
      }
      } : name => {
      github_config_url    = "https://github.com/cconstantine/smelt"
      github_config_secret = "arc-github-pat-smelt"
      platform             = "amd64"
      host_storage = {
        nodes = ["homelab", "system76", "cachyos-x8664"]
        path  = r.dir
      }
      dind_resources = r.resources
      min_runners    = 0
      max_runners    = 2
    } }
  )

  # dind's command on amd64, in place of the docker:dind entrypoint (taken
  # from smelt's docker/sandbox/start-dockerd.sh). A privileged container
  # shares the node's cgroup namespace here, so /sys/fs/cgroup is the node's
  # whole tree: the dind entrypoint, assuming a private one, moved every
  # process in the node's root cgroup into /init and enabled controllers at
  # the node's root, and dockerd then put a job's containers under /docker at
  # the node's root -- outside the pod, its requests and limits, and
  # Prometheus. This keeps dockerd and every container it starts inside the
  # dind container's own cgroup, and writes nowhere else. Runs as `sh -c
  # <this> start-dockerd <dockerd args>`.
  nested_dockerd = <<-EOT
    set -eu
    self=$(sed -n 's/^0:://p' /proc/self/cgroup)
    base=/sys/fs/cgroup$self
    mkdir -p "$base/dockerd"
    # cgroup v2: a cgroup whose children get controllers can't hold
    # processes itself, so move ours into a leaf first. Retried: an exec
    # probe can land a new process in $base between the move and the write.
    until {
      for pid in $(cat "$base/cgroup.procs"); do
        echo "$pid" > "$base/dockerd/cgroup.procs" 2>/dev/null || :
      done
      sed -e 's/ / +/g' -e 's/^/+/' < "$base/cgroup.controllers" > "$base/cgroup.subtree_control"
    } 2>/dev/null; do
      sleep 0.1
    done
    # As the dind entrypoint does; only this container's mount namespace.
    mount --make-rshared /
    exec dockerd --cgroup-parent="$self/docker" "$@"
  EOT

  # Mounted at the same path in the runner and dind containers, so a job can
  # bind-mount it into its own containers. Runners with host_storage get one.
  ci_cache_path = "/home/runner/ci-cache"
}

resource "kubernetes_secret" "arc_github_pat" {
  metadata {
    name      = "arc-github-pat"
    namespace = kubernetes_namespace.arc_runners.metadata.0.name
  }

  data = {
    github_token = var.github_pat
  }
}

resource "kubernetes_secret" "arc_github_pat_smelt" {
  metadata {
    name      = "arc-github-pat-smelt"
    namespace = kubernetes_namespace.arc_runners.metadata.0.name
  }

  data = {
    github_token = var.github_pat_smelt
  }
}

resource "helm_release" "arc_controller" {
  name       = "arc"
  namespace  = kubernetes_namespace.arc.metadata.0.name
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set-controller"
  version    = "0.14.0"

  values = [yamlencode({
    resources = {
      requests = { cpu = "10m", memory = "64Mi" }
      limits   = { memory = "96Mi" }
    }
  })]

  wait = true
}

resource "kubernetes_persistent_volume_claim" "arc_docker_data" {
  for_each         = { for k, v in local.runner_targets : k => v if v.host_storage == null }
  wait_until_bound = false
  metadata {
    name      = "arc-docker-data-${each.key}"
    namespace = kubernetes_namespace.arc_runners.metadata.0.name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "local-path"
    resources {
      requests = {
        storage = "50Gi"
      }
    }
  }
}

resource "helm_release" "arc_runner_set" {
  for_each   = local.runner_targets
  name       = "arc-runner-${each.key}"
  namespace  = kubernetes_namespace.arc_runners.metadata.0.name
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set"
  version    = "0.14.0"

  depends_on = [
    helm_release.arc_controller,
    kubernetes_secret.arc_github_pat,
    kubernetes_secret.arc_github_pat_smelt,
  ]

  values = [yamlencode({
    githubConfigUrl    = each.value.github_config_url
    githubConfigSecret = each.value.github_config_secret
    runnerScaleSetName = "arc-runner-${each.key}"
    minRunners         = each.value.min_runners
    maxRunners         = each.value.max_runners
    # Keep the listener on an x86_64 node; left to the scheduler it can land
    # on an arm node, where it couldn't resolve api.github.com (pixo-8, since removed).
    listenerTemplate = {
      spec = {
        nodeSelector = {
          "kubernetes.io/arch" = "amd64"
        }
        containers = [{ name = "listener" }]
      }
    }
    template = {
      spec = {
        nodeSelector = {
          "kubernetes.io/arch" = local.runner_node_arch[each.value.platform]
        }
        # Only nodes that keep a copy of the cache (host_storage.nodes), and
        # never two of this set's runners on one node: they'd share its
        # cache directories.
        affinity = each.value.host_storage == null ? null : {
          nodeAffinity = {
            requiredDuringSchedulingIgnoredDuringExecution = {
              nodeSelectorTerms = [{
                matchExpressions = [{
                  key      = "kubernetes.io/hostname"
                  operator = "In"
                  values   = each.value.host_storage.nodes
                }]
              }]
            }
          }
          podAntiAffinity = {
            requiredDuringSchedulingIgnoredDuringExecution = [{
              topologyKey = "kubernetes.io/hostname"
              labelSelector = {
                matchLabels = { "actions.github.com/scale-set-name" = "arc-runner-${each.key}" }
              }
            }]
            # And, where there's room, not beside another host_storage set's
            # runner (smelt's server and browser jobs): each is several cores
            # and ~10GiB of cargo, Postgres and k3s.
            preferredDuringSchedulingIgnoredDuringExecution = [{
              weight = 100
              podAffinityTerm = {
                topologyKey = "kubernetes.io/hostname"
                labelSelector = {
                  matchExpressions = [{
                    key      = "actions.github.com/scale-set-name"
                    operator = "In"
                    values   = [for k, t in local.runner_targets : "arc-runner-${k}" if t.host_storage != null && k != each.key]
                  }]
                }
              }
            }]
          }
        }
        initContainers = concat(each.value.host_storage == null ? [] : [
          {
            # hostPath creates the cache dir root-owned; the runner user
            # (1001) writes it.
            name            = "own-ci-cache"
            image           = "docker:dind"
            command         = ["chown", "1001:1001", "/ci-cache"]
            securityContext = { runAsUser = 0 }
            volumeMounts    = [{ name = "ci-cache", mountPath = "/ci-cache" }]
          },
          ], [
          {
            name    = "init-dind-externals"
            image   = "ghcr.io/actions/actions-runner:latest"
            command = ["cp", "-r", "/home/runner/externals/.", "/home/runner/tmpDir/"]
            volumeMounts = [{
              name      = "dind-externals"
              mountPath = "/home/runner/tmpDir"
            }]
          },
          merge(
            {
              name  = "dind"
              image = each.value.platform == "arm64" || each.value.platform == "armv7" ? "docker:26-dind" : "docker:dind"
              env = [{
                name  = "DOCKER_GROUP_GID"
                value = "123"
              }]
              securityContext = {
                privileged = true
              }
              restartPolicy = "Always"
              startupProbe = {
                exec = {
                  command = ["docker", "info"]
                }
                initialDelaySeconds = 0
                failureThreshold    = 24
                periodSeconds       = 5
              }
              volumeMounts = concat([
                { name = "work", mountPath = "/home/runner/_work" },
                { name = "dind-sock", mountPath = "/var/run" },
                { name = "dind-externals", mountPath = "/home/runner/externals" },
                { name = "dind-docker", mountPath = "/var/lib/docker" }
              ], each.value.host_storage != null ? [{ name = "ci-cache", mountPath = local.ci_cache_path }] : [])
            },
            each.value.platform == "arm64" || each.value.platform == "armv7" ? {
              command = ["sh", "-c"]
              args    = ["apk add --no-cache iptables-legacy && for cmd in iptables ip6tables iptables-save iptables-restore ip6tables-save ip6tables-restore; do ln -sf /usr/sbin/xtables-legacy-multi /usr/sbin/$cmd; done && exec dockerd-entrypoint.sh dockerd --host=unix:///var/run/docker.sock --group=123 --mtu=1450 --default-network-opt=bridge=com.docker.network.driver.mtu=1450"]
              } : {
              command = ["sh", "-c", local.nested_dockerd, "start-dockerd"]
              args    = ["--host=unix:///var/run/docker.sock", "--group=$(DOCKER_GROUP_GID)", "--mtu=1450", "--default-network-opt=bridge=com.docker.network.driver.mtu=1450"]
            },
            each.value.dind_resources == null ? {} : { resources = each.value.dind_resources },
          )
        ])
        containers = [
          {
            name    = "runner"
            image   = "ghcr.io/actions/actions-runner:latest"
            command = ["/home/runner/run.sh"]
            env = concat([
              {
                name  = "DOCKER_HOST"
                value = "unix:///var/run/docker.sock"
              },
              {
                name  = "RUNNER_WAIT_FOR_DOCKER_IN_SECONDS"
                value = "120"
              }
            ], each.value.host_storage != null ? [{ name = "CI_CACHE_DIR", value = local.ci_cache_path }] : [])
            volumeMounts = concat([
              { name = "work", mountPath = "/home/runner/_work" },
              { name = "dind-sock", mountPath = "/var/run" },
              { name = "dind-externals", mountPath = "/home/runner/externals" }
            ], each.value.host_storage != null ? [{ name = "ci-cache", mountPath = local.ci_cache_path }] : [])
          }
        ]
        volumes = concat([
          { name = "dind-sock", emptyDir = {} },
          { name = "dind-externals", emptyDir = {} },
          { name = "work", emptyDir = {} },
          ],
          each.value.host_storage == null ? [{
            name = "dind-docker"
            persistentVolumeClaim = {
              claimName = kubernetes_persistent_volume_claim.arc_docker_data[each.key].metadata.0.name
            }
          }] : [],
          each.value.host_storage == null ? [] : [{
            name     = "dind-docker"
            hostPath = { path = "${each.value.host_storage.path}/docker", type = "DirectoryOrCreate" }
          }],
          each.value.host_storage == null ? [] : [{
            name     = "ci-cache"
            hostPath = { path = "${each.value.host_storage.path}/ci-cache", type = "DirectoryOrCreate" }
        }])
      }
    }
  })]
}
