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
    } },
    { "smelt-amd64" = {
      github_config_url    = "https://github.com/cconstantine/smelt"
      github_config_secret = "arc-github-pat-smelt"
      platform             = "amd64"
    } }
  )
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
  for_each         = local.runner_targets
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
    template = {
      spec = {
        nodeSelector = {
          "kubernetes.io/arch" = local.runner_node_arch[each.value.platform]
        }
        initContainers = [
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
              volumeMounts = [
                { name = "work", mountPath = "/home/runner/_work" },
                { name = "dind-sock", mountPath = "/var/run" },
                { name = "dind-externals", mountPath = "/home/runner/externals" },
                { name = "dind-docker", mountPath = "/var/lib/docker" }
              ]
            },
            each.value.platform == "arm64" || each.value.platform == "armv7" ? {
              command = ["sh", "-c"]
              args    = ["apk add --no-cache iptables-legacy && for cmd in iptables ip6tables iptables-save iptables-restore ip6tables-save ip6tables-restore; do ln -sf /usr/sbin/xtables-legacy-multi /usr/sbin/$cmd; done && exec dockerd-entrypoint.sh dockerd --host=unix:///var/run/docker.sock --group=123 --mtu=1450"]
              } : {
              args = ["dockerd", "--host=unix:///var/run/docker.sock", "--group=$(DOCKER_GROUP_GID)", "--mtu=1450"]
            }
          )
        ]
        containers = [
          {
            name    = "runner"
            image   = "ghcr.io/actions/actions-runner:latest"
            command = ["/home/runner/run.sh"]
            env = [
              {
                name  = "DOCKER_HOST"
                value = "unix:///var/run/docker.sock"
              },
              {
                name  = "RUNNER_WAIT_FOR_DOCKER_IN_SECONDS"
                value = "120"
              }
            ]
            volumeMounts = [
              { name = "work", mountPath = "/home/runner/_work" },
              { name = "dind-sock", mountPath = "/var/run" },
              { name = "dind-externals", mountPath = "/home/runner/externals" }
            ]
          }
        ]
        volumes = [
          { name = "dind-sock", emptyDir = {} },
          { name = "dind-externals", emptyDir = {} },
          { name = "work", emptyDir = {} },
          {
            name = "dind-docker"
            persistentVolumeClaim = {
              claimName = kubernetes_persistent_volume_claim.arc_docker_data[each.key].metadata.0.name
            }
          },
        ]
      }
    }
  })]
}
