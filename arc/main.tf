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
    # (see nested_dockerd). Measured over the fortnight to 2026-11-19, from
    # the jobs' own memory reports (SME-578) and cAdvisor: server's dind
    # peaked at 14.2GiB and ~5.9 cores, browser's at 13.3GiB and 2.6 cores
    # (its cargo build caps its jobs' memory, SME-575) -- against the old
    # 16Gi/14Gi limits that was 88% and 95%: memory includes the page cache
    # the builds want, and a cgroup that full makes every allocation compete
    # with reclaim. Anonymous-only, the peaks are under 5.5GiB each, so the
    # limits are headroom, not expectation. Requests sit at the working set
    # the jobs actually hold: with the node OOM-killing by the hundred a day
    # since Nov 16 (runners and smelt's sandboxes sharing these nodes), an
    # honest request at least makes the runners schedulable with intent and
    # ranks them properly for eviction. No CPU limit: a cold build uses
    # every idle core.
    #
    # Runners exist only while jobs run (min 0), so the reservations are
    # held only then; a job waits about a minute for its pod. Up to three per
    # job, so three PRs can build at once (2026-11-25; was two), one per node
    # of host_storage.nodes (podAntiAffinity below): two dockerds can't share
    # a node's cache directory. All six fit only while system76 takes a
    # browser runner and the other three each take a server and a browser
    # runner: with framework away, or a sandbox (18.25Gi) on cachyos-x8664,
    # the third server runner waits for room.
    { for name, r in {
      "smelt-amd64" = {
        dir = "/var/lib/arc-runner-smelt"
        resources = {
          requests = { cpu = "5", memory = "12Gi" }
          limits   = { memory = "20Gi" }
        }
      }
      "smelt-amd64-browser" = {
        dir = "/var/lib/arc-runner-smelt-browser"
        resources = {
          requests = { cpu = "3", memory = "10Gi" }
          limits   = { memory = "16Gi" }
        }
      }
      } : name => {
      github_config_url    = "https://github.com/cconstantine/smelt"
      github_config_secret = "arc-github-pat-smelt"
      platform             = "amd64"
      # framework is the laptop, which leaves the network: a job running there
      # then just fails and can be re-run. Its first run there, and each after
      # it's been away a while, starts with a cold cache.
      host_storage = {
        nodes = ["homelab", "system76", "cachyos-x8664", "framework"]
        path  = r.dir
      }
      dind_resources = r.resources
      min_runners    = 0
      max_runners    = 3
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

# The controller and the listeners are small, always-on and not
# performance-critical, so they prefer xavier-vm (see xavier-vm.tf) and leave
# memory requests on the busier nodes. Only a preference: if xavier-vm drops
# off the network they reschedule elsewhere instead of waiting for it.
locals {
  prefer_xavier_vm = {
    tolerations = [{
      key      = "homelab/vm"
      operator = "Equal"
      value    = "firecracker"
      effect   = "PreferNoSchedule"
    }]
    affinity = {
      nodeAffinity = {
        preferredDuringSchedulingIgnoredDuringExecution = [{
          weight = 100
          preference = {
            matchExpressions = [{
              key      = "homelab/vm"
              operator = "In"
              values   = ["firecracker"]
            }]
          }
        }]
      }
    }
  }
}

resource "helm_release" "arc_controller" {
  name       = "arc"
  namespace  = kubernetes_namespace.arc.metadata.0.name
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set-controller"
  version    = "0.14.0"

  values = [yamlencode(merge(local.prefer_xavier_vm, {
    resources = {
      requests = { cpu = "10m", memory = "64Mi" }
      limits   = { memory = "96Mi" }
    }
  }))]

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
    # Listeners prefer xavier-vm (local.prefer_xavier_vm). They used to be
    # pinned to amd64 because pixo-8 (an arm node, since removed) couldn't
    # resolve api.github.com; xavier-vm's own runners reach GitHub fine.
    listenerTemplate = {
      spec = {
        tolerations = local.prefer_xavier_vm.tolerations
        affinity    = local.prefer_xavier_vm.affinity
        containers = [{
          name = "listener"
          # It only polls GitHub for jobs and watches the scale set; it is
          # idle by design, and no request made it evictable first, as for
          # the runner container below.
          resources = {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { memory = "512Mi" }
          }
        }]
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
              image = "docker:dind"
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
            # Every platform starts dockerd the same way. The arm runners used
            # to pin docker:26-dind with iptables-legacy for xavier's L4T host
            # kernel; on xavier-vm (6.18, cgroup v2, nftables) they don't.
            {
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
            # The runner process and the job's non-docker steps (checkout,
            # git, node actions) peaked at 0.35GiB and under a core over a
            # fortnight. It had no resources at all before: invisible to the
            # scheduler, and first in line for eviction, since usage against
            # no request reads as unbounded over-commit. The limit is headroom
            # for a build step that forgets to run under dind.
            resources = {
              requests = { cpu = "250m", memory = "512Mi" }
              limits   = { memory = "2Gi" }
            }
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

# smelt's sub-minute jobs that need no Docker daemon (SME-753): ci.yml's
# `changes`, publish-images.yml's `source` and its two manifest jobs. A plain
# runner, no dind: those jobs waited 94-633 s for room on the dind sets
# (10-12Gi each) while the median runner pod peaked at 0.2GiB. A job that
# needs Docker stays on arc-runner-smelt-amd64(-browser): there is no daemon
# here. Not in runner_targets, whose template always adds dind.
resource "helm_release" "arc_runner_set_smelt_light" {
  name       = "arc-runner-smelt-amd64-light"
  namespace  = kubernetes_namespace.arc_runners.metadata.0.name
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set"
  version    = "0.14.0"

  depends_on = [
    helm_release.arc_controller,
    kubernetes_secret.arc_github_pat_smelt,
  ]

  values = [yamlencode({
    githubConfigUrl    = "https://github.com/cconstantine/smelt"
    githubConfigSecret = kubernetes_secret.arc_github_pat_smelt.metadata.0.name
    runnerScaleSetName = "arc-runner-smelt-amd64-light"
    minRunners         = 0
    # Three PRs' worth of these at once, with room for publish jobs.
    maxRunners = 6
    listenerTemplate = {
      spec = {
        tolerations = local.prefer_xavier_vm.tolerations
        affinity    = local.prefer_xavier_vm.affinity
        containers = [{
          name = "listener"
          resources = {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { memory = "512Mi" }
          }
        }]
      }
    }
    template = {
      spec = {
        nodeSelector = { "kubernetes.io/arch" = "amd64" }
        containers = [{
          name    = "runner"
          image   = "ghcr.io/actions/actions-runner:latest"
          command = ["/home/runner/run.sh"]
          resources = {
            requests = { cpu = "500m", memory = "1Gi" }
            limits   = { memory = "2Gi" }
          }
        }]
      }
    }
  })]
}
