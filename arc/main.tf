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
    } },
    # One runner per smelt CI job, so the jobs run side by side and each
    # keeps a cache of its own; ci.yml names them. Docker storage and the CI
    # build cache (see ci_cache_path) are on the node's own disk rather than
    # local-path PVCs: those live on homelab's SATA SSD with the rest of k3s,
    # which smelt's tests kept 95-100% busy. This path is on its NVMe root
    # disk, and every runner needs its own: two dockerds can't share one.
    { for name, dir in {
      "smelt-amd64"         = "/var/lib/arc-runner-smelt"
      "smelt-amd64-browser" = "/var/lib/arc-runner-smelt-browser"
      } : name => {
      github_config_url    = "https://github.com/cconstantine/smelt"
      github_config_secret = "arc-github-pat-smelt"
      platform             = "amd64"
      host_storage = {
        node = "homelab"
        path = dir
      }
    } }
  )

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
    minRunners         = 1
    maxRunners         = 1
    # Keep the listener on an x86_64 node; left to the scheduler it can land
    # on an arm node like pixo-8, where it can't resolve api.github.com.
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
        nodeSelector = merge(
          { "kubernetes.io/arch" = local.runner_node_arch[each.value.platform] },
          each.value.host_storage == null ? {} : { "kubernetes.io/hostname" = each.value.host_storage.node },
        )
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
              args = ["dockerd", "--host=unix:///var/run/docker.sock", "--group=$(DOCKER_GROUP_GID)", "--mtu=1450", "--default-network-opt=bridge=com.docker.network.driver.mtu=1450"]
            }
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
