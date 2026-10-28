# Strata (https://github.com/Niko1221/Strata) on ryzen, replacing
# llama-cpp-ryzen (scaled to 0 in llama_cpp.tf) for Qwen3.8-Flash-Next.
# Strata is an inference engine built for this one MoE: it keeps the hot
# experts in VRAM (pre-filled from a routing profile), computes the misses on
# the CPU, and drafts tokens with the model's MTP layer. Same R9700, same
# model, measured against llama.cpp's best split (--n-cpu-moe 40 plus its
# --moe-cache-mib expert cache; see llama_cpp.tf):
#
#                          llama.cpp+cache   strata IQ3_S
#   ~4k prompt   pp / tg    449 / 29 tok/s   2105 / 82 tok/s
#   34k prompt   pp / tg    398 / 26         1980 / 55
#   ~231k ctx    pp / tg    286 / 12.5       2089 / 75
#
# Both pass the near-full-context probe from llama_cpp.tf (a fact buried
# early in ~231k tokens, asked for at the end). A 231k-token prompt reads in
# ~2 minutes instead of ~14. Like llama-cpp-ryzen, it answers one request at
# a time.
#
# Strata runs ISTA-DASLab's GSQ-RCO quants and unsloth's UD-IQ4_XS and up,
# not the UD-Q3_K_XL llama.cpp used. Two of them fit ryzen's RAM alongside
# everything else there with every expert in RAM: ISTA's IQ3_S (Strata holds
# ~62GB) and unsloth's UD-IQ4_XS (~5GB more); see strata_models. UD-Q4_K_XL's
# 72GB of experts don't, so Strata would read part of them from the SSD.
#
# The served model name is Strata's own (GET /v1/models, e.g.
# qwen3.8-flash-next-iq3_s); the name in a request is ignored. Clients need
# the API key:
#   kubectl -n ai get secret strata-ryzen -o jsonpath='{.data.API_KEY}' | base64 -d
# /metrics (vLLM-style names) needs the key too; Prometheus reads it from the
# strata_api_key output.

locals {
  # The served size: a key of strata_models. Each keeps its own folder, so
  # switching back is this line and a restart.
  strata_model = "UD-IQ4_XS"

  strata_models = {
    IQ3_S = {
      family  = ""
      hf_path = "ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF/resolve/ed59f92082b1e93c0e96d60a8b11aab089b52f09/IQ3_S"
      # name -> sha256, as pinned in Strata's setup.py (ISTA_FILES)
      files = {
        "Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf" = "4c1eb2ceb4915e1192f4f386021897bde56a97f40a0bb78bb86465e0f7d2aca3"
        "Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00002-of-00002.gguf" = "316b46f3a2dbd68c900f43136ab9449f9dcc3725dfd8c794847c204bc161e113"
      }
      # Engine flags for this size, on top of strata_user_args (flag -> value).
      # A fixed expert-cache size, in slots: --expert-cache auto overshoots on
      # the R9700 at 256K context: it sizes for ~10k slots, then grows the
      # cache to ~13.3k (25GB) and leaves too little VRAM for the MTP draft
      # head and the verify buffers, so the engine exits while loading ("the
      # draft head does not fit" / "the device arena (75 MiB) does not fit").
      # 9500 starts reliably (it ends up holding ~12.4k slots, 23.5GB, as
      # smaller blobs pack in).
      args = { "--expert-cache" = "9500" }
    }
    # Unsloth's ~4-bit file: IQ3_S gate/up experts with IQ4_NL downs (Q8_0 in
    # five layers). Closer to the full model than ISTA's IQ3_S (mean KL vs
    # Q8_0 0.101 instead of 0.144, Strata's docs/QUANTS.md); ~5GB more RAM.
    "UD-IQ4_XS" = {
      family  = "unsloth"
      hf_path = "unsloth/Qwen3.8-Flash-Next-GGUF/resolve/38bb39ee97821de2c9009abb7e93950eec396e66/UD-IQ4_XS"
      # name -> sha256, as pinned in Strata's setup.py (UNSLOTH_IQ4_XS_SHARDS)
      files = {
        "Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf" = "5ce89370720f8bf90890f439361282104c1aa1482d4013bb9a50923e758e71a4"
        "Qwen3.8-Flash-Next-UD-IQ4_XS-00002-of-00003.gguf" = "577a38a2392b40ca2193cea502e1d92f60b8cd370675d308e0ec21885d9daaa7"
        "Qwen3.8-Flash-Next-UD-IQ4_XS-00003-of-00003.gguf" = "d4634e6d84f0ebb0940be15c90d3790bf6464e3dea3a1cddc567dc0e83ad8833"
      }
      # Setup picks --ple-io ram for this file: the 27GiB n-gram table copied
      # into RAM beside the 55GiB of experts, ~85GB at load, and the kernel
      # killed the engine. mmap reads it from the NVMe as IQ3_S's is. The
      # expert cache is left to the engine until a start shows it overshoots.
      args = { "--ple-io" = "mmap" }
    }
  }

  strata           = local.strata_models[local.strata_model]
  strata_model_dir = "/var/lib/rancher/strata/models/${local.strata_model}"
  strata_files     = local.strata.files
  strata_hf_path   = local.strata.hf_path

  # Engine flags for every size, written to the run settings' "user_args",
  # which Strata applies over the args setup generates at every start (and
  # keeps when setup runs again). Per-size flags (strata_models' args) follow.
  strata_user_args = concat([
    # Park (keep resumable) only conversations of 8K tokens or more, so short
    # side requests don't push a long parent conversation out.
    "--conversation-cache-min-tokens", "8192",
    # Keep prompt checkpoints spread back from the conversation's end: an
    # agent that rewrites its history a few thousand tokens back resumes near
    # the edit. Same RAM.
    "--prompt-cache-spread",
    # The English/code draft vocabulary: 81MiB of VRAM instead of 213MiB for
    # the default CJK one -- part of what makes 256K context fit.
    "--mtp-draft-vocab", "/opt/strata/terminal/data/draft_vocab_en.bin",
  ], flatten([for flag, value in local.strata.args : [flag, value]]))

  # Top-level server settings in the run settings (not engine flags).
  strata_server_settings = {
    # Also read a declared tool's call written in a near-miss form (JSON in
    # <tool_call>, a <function=...> block without <tool_call>, ...). Strata's
    # agent turns: 98.3% read as intended with it, 92.9% without.
    tool_call_recovery = true
  }
}

resource "random_password" "strata_api_key" {
  length  = 48
  special = false
}

resource "kubernetes_secret" "strata_ryzen" {
  metadata {
    name      = "strata-ryzen"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }

  data = {
    API_KEY = random_password.strata_api_key.result
  }
}

resource "kubernetes_ingress_v1" "strata_ryzen" {
  metadata {
    name      = "strata-ryzen"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }

  spec {
    rule {
      host = "strata-ryzen.${var.domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service_v1.strata_ryzen.metadata.0.name
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_ingress_v1" "strata_ryzen_tls" {
  metadata {
    name      = "strata-ryzen-tls"
    namespace = kubernetes_namespace.namespace.metadata.0.name
    annotations = {
      "traefik.ingress.kubernetes.io/router.middlewares" = "cert-manager-redirect-https@kubernetescrd,cert-manager-hsts-headers@kubernetescrd"
    }
  }

  spec {
    rule {
      host = "strata-ryzen.${var.tls_domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service_v1.strata_ryzen.metadata.0.name
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "strata_ryzen" {
  metadata {
    name      = "strata-ryzen"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    selector = {
      name = "strata-ryzen"
    }
    port {
      port        = 8080
      target_port = 8080
    }
  }
}

resource "kubernetes_deployment_v1" "strata_ryzen" {
  wait_for_rollout = false
  metadata {
    name      = "strata-ryzen"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = {
        name = "strata-ryzen"
      }
    }

    template {
      metadata {
        labels = {
          name = "strata-ryzen"
        }
      }
      spec {
        node_selector = {
          "amd.com/gpu.type"       = "r9700"
          "kubernetes.io/hostname" = "ryzen"
        }

        # Strata's docker/compose files ask for a two-minute stop.
        termination_grace_period_seconds = 120

        # Same downloader as llama-cpp-ryzen's, plus a check against Strata's
        # pinned hashes (a wrong file would otherwise only show up as a
        # failed "prepare" step minutes into the first start).
        init_container {
          name  = "init-model"
          image = "curlimages/curl:8.11.1"
          command = ["sh", "-c", <<-EOT
            set -e
            apk add --no-cache aria2 coreutils >/dev/null
            cd /models
            %{for f, sum in local.strata_files~}
            if [ ! -f ${f} ]; then
              echo "downloading ${f}"
              aria2c -x8 -s8 -k1M -c --max-tries=20 --retry-wait=10 \
                --file-allocation=none --summary-interval=30 \
                -d /models -o ${f} "https://huggingface.co/${local.strata_hf_path}/${f}"
              echo "${sum}  ${f}" | sha256sum -c
            fi
            %{endfor~}
          EOT
          ]
          security_context {
            run_as_user = 0
          }
          volume_mount {
            name       = "strata-models"
            mount_path = "/models"
          }
        }

        container {
          name  = "strata"
          image = "ghcr.io/niko1221/strata:0.2.7-rocm-gfx120x"

          # Wraps the image's entrypoint (tini -> entrypoint.sh run) for what
          # its env vars can't set:
          #  - memlock: Strata pins host memory for the experts and the
          #    streamed K/V; the container default here is 8MiB.
          #  - strata_user_args and strata_server_settings, written into the
          #    served model's saved run settings (the ones whose args name its
          #    first file), which launch reads. They don't exist before the
          #    first start has prepared the model, so a new size may need one
          #    restart to pick these up.
          command = ["/bin/sh", "-c", <<-EOT
            ulimit -l unlimited
            /opt/strata/terminal/python/bin/python3 -c '
            import glob, json, sys
            want, user_args, settings = sys.argv[1], json.loads(sys.argv[2]), json.loads(sys.argv[3])
            for p in glob.glob("/data/install/strata-*.json"):
                d = json.load(open(p))
                if not any(want in x for x in d["args"]):
                    continue
                d["draft_vocab"] = "en"
                d["user_args"] = user_args
                d.update(settings)
                json.dump(d, open(p, "w"), indent=1)
            ' "${sort(keys(local.strata_files))[0]}" '${jsonencode(local.strata_user_args)}' '${jsonencode(local.strata_server_settings)}'
            exec /usr/bin/tini -- /opt/strata/entrypoint.sh run
          EOT
          ]

          env {
            name  = "MODEL"
            value = local.strata_model
          }
          dynamic "env" {
            for_each = local.strata.family != "" ? [local.strata.family] : []
            content {
              name  = "FAMILY"
              value = env.value
            }
          }
          env {
            name  = "MODEL_PATH"
            value = "/models"
          }
          env {
            name  = "CONTEXT"
            value = "256k"
          }
          env {
            name  = "PARALLEL"
            value = "1"
          }
          env {
            name  = "VISION"
            value = "off"
          }
          env {
            name  = "TUNE"
            value = "skip"
          }
          # Route tail skip (on by default on RDNA4) leaves out a missed expert
          # that every token of a verify window ranks 7th or lower: faster on
          # cards that miss often, but the answers drift from the model's. Here
          # 97-99% of experts hit VRAM, so it saved little, and long agent
          # conversations started writing the wrong tool's name.
          env {
            name  = "STRATA_ROUTE_TAIL_SKIP"
            value = "0"
          }
          # One log line per finished request.
          env {
            name  = "STRATA_REQUEST_LINES"
            value = "1"
          }
          env {
            name = "API_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.strata_ryzen.metadata.0.name
                key  = "API_KEY"
              }
            }
          }

          port {
            container_port = 8080
          }

          # The image's own HEALTHCHECK: GET /v1/models with the key.
          readiness_probe {
            exec {
              command = ["/opt/strata/healthcheck.sh"]
            }
            period_seconds  = 15
            timeout_seconds = 8
          }

          security_context {
            capabilities {
              add = ["IPC_LOCK", "SYS_RESOURCE"]
            }
          }

          resources {
            limits = {
              "amd.com/r9700" = "1"
            }
            requests = {
              "amd.com/r9700" = "1"
            }
          }

          volume_mount {
            name       = "strata-models"
            mount_path = "/models"
            read_only  = true
          }
          volume_mount {
            name       = "strata-data"
            mount_path = "/data"
          }
          volume_mount {
            name       = "shm"
            mount_path = "/dev/shm"
          }
        }

        volume {
          name = "strata-models"
          host_path {
            path = local.strata_model_dir
            type = "DirectoryOrCreate"
          }
        }
        # Prepared pack, MTP draft layer, run settings and logs.
        volume {
          name = "strata-data"
          host_path {
            path = "/var/lib/rancher/strata/data"
            type = "DirectoryOrCreate"
          }
        }
        volume {
          name = "shm"
          empty_dir {
            medium     = "Memory"
            size_limit = "2Gi"
          }
        }
      }
    }
  }
}

# For Prometheus's scrape of /metrics (monitoring/config/prometheus.yml).
output "strata_api_key" {
  value     = random_password.strata_api_key.result
  sensitive = true
}
