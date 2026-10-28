# llama.cpp server on ryzen, replacing ollama-ryzen (scaled to 0 in
# ollama.tf). Uses the upstream ggml-org ROCm image on ryzen's Radeon AI
# PRO R9700 (32GB, gfx1201) -- the ROCm userspace ships in the image, so the
# host only needs the amdgpu kernel driver. The GPU is exposed as
# amd.com/r9700 by amd-device-plugin.
#
# ROCm vs Vulkan (server-vulkan), flash-next, 2.5k-token prompt, 256 gen:
#   vulkan  ~589 tok/s prompt, 24.8 tok/s gen, ~15s model load
#   rocm    ~595 tok/s prompt, 27.2 tok/s gen, ~79s model load
# Vulkan also pins CPU-resident weights as GTT (~47GB); ROCm doesn't.

locals {
  # Which model llama-cpp-ryzen serves. Flip llama_cpp_model and re-apply.
  #
  #   flash-next     Qwen3.8-Flash-Next UD-Q3_K_XL (~90GB, ~4B active, hybrid
  #                  attention). Hardware-matched: tiny active expert set.
  #                  Quant-size swept on the R9700 against a near-full
  #                  262144-ctx correctness probe (a fact buried early in a
  #                  ~240k-token document, asked for back at the end), not
  #                  just a short-prompt throughput check:
  #                    UD-Q2_K_XL (~79GB): passes, 24.8 tok/s -- previously
  #                      the deployed quant, now one notch below best verified.
  #                    UD-Q3_K_XL (~90GB): passes, 22.4 tok/s -- picked: the
  #                      largest quant that passes, for ~10% less speed.
  #                    UD-Q4_K_XL (~111GB): FAILS the near-full-context probe
  #                      (immediate empty response, reproduced twice) despite
  #                      being higher-precision and despite using the same
  #                      q8_0 KV cache that works at Q2/Q3. Cause not
  #                      understood (quant-specific vs. the specific
  #                      --n-cpu-moe split tried) -- do not use until this is
  #                      explained.
  #                    UD-Q5_K_XL (~158GB) and up: hard ceiling, not a tuning
  #                      problem. Crash-loops (SIGKILL/137, kernel OOM) a few
  #                      minutes into loading on every offload split tried,
  #                      including an all-CPU fallback. Ryzen has 93GB RAM;
  #                      this quant's CPU-resident portion alone exceeds that
  #                      regardless of how much the R9700's 32GB VRAM holds.
  #                  Good general/agentic model, but massively overkill (and
  #                  too slow, ~20-25 tok/s, single stream only) for
  #                  high-volume short-text classification.
  #
  #   qwen3-235b     Qwen3-235B-A22B Q4_K_M (~142GB, 22B active). TRIED IT:
  #                  cold-cache measured 0.46 tok/s prompt / 0.59 tok/s gen
  #                  -- far worse than hoped, confirms it doesn't fit this
  #                  box. Model files removed from ryzen; re-downloading
  #                  needed if revisited.
  #
  #   qwen3-4b       Qwen3-4B-Instruct-2507 Q8_0 (~4.3GB). Non-thinking
  #                  instruct variant (no <think> overhead) -- entirely fits
  #                  in the 3070's 8GB VRAM alongside KV cache, so it runs
  #                  fully GPU-resident with room for --parallel batching.
  #                  Picked as the classification model: best accuracy/speed
  #                  balance of the small Qwen3 sizes for a short-message,
  #                  fixed-label-set categorization task.
  #
  #   qwen3-1.7b     Qwen3-1.7B Q8_0 (~1.9GB). Fallback if qwen3-4b's
  #                  throughput isn't enough for the 100k+/day volume --
  #                  roughly 2-3x the tok/s of qwen3-4b with a real but
  #                  smaller accuracy hit on nuanced category boundaries.
  #
  #   qwen3-0.6b     Qwen3-0.6B Q8_0 (~0.6GB). Max-throughput fallback;
  #                  only worth it if even qwen3-1.7b can't keep up, and
  #                  needs the most careful prompt/few-shot tuning to stay
  #                  "accurate enough".
  llama_cpp_model = "flash-next"

  llama_cpp_models = {
    flash-next = {
      hf_path = "unsloth/Qwen3.8-Flash-Next-GGUF/resolve/main/UD-Q3_K_XL"
      files   = [for i in range(1, 4) : "Qwen3.8-Flash-Next-UD-Q3_K_XL-0000${i}-of-00003.gguf"]
    }
    qwen3-235b = {
      hf_path = "unsloth/Qwen3-235B-A22B-GGUF/resolve/main/Q4_K_M"
      files   = [for i in range(1, 4) : "Qwen3-235B-A22B-Q4_K_M-0000${i}-of-00003.gguf"]
    }
    qwen3-4b = {
      hf_path = "unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main"
      files   = ["Qwen3-4B-Instruct-2507-Q8_0.gguf"]
    }
    "qwen3-1.7b" = {
      hf_path = "unsloth/Qwen3-1.7B-GGUF/resolve/main"
      files   = ["Qwen3-1.7B-Q8_0.gguf"]
    }
    "qwen3-0.6b" = {
      hf_path = "unsloth/Qwen3-0.6B-GGUF/resolve/main"
      files   = ["Qwen3-0.6B-Q8_0.gguf"]
    }
  }

  llama_cpp_m       = local.llama_cpp_models[local.llama_cpp_model]
  llama_cpp_model_0 = local.llama_cpp_m.files[0]
  # Small single-file classification models fit entirely in VRAM, so batch
  # requests via continuous batching instead of the single-stream setup
  # flash-next needed. Ignored (harmlessly) if flash-next/qwen3-235b are
  # selected, though those don't fit VRAM well enough to benefit anyway.
  llama_cpp_parallel = contains(["qwen3-4b", "qwen3-1.7b", "qwen3-0.6b"], local.llama_cpp_model) ? 32 : 1
  llama_cpp_ctx_size = contains(["qwen3-4b", "qwen3-1.7b", "qwen3-0.6b"], local.llama_cpp_model) ? 32768 : 262144

  # smelt's llama.cpp provider has this exact alias registered as its
  # model (see smelt's /providers page) -- keep it stable across a model
  # swap within flash-next's own quant ladder so smelt's existing
  # conversations/provider config don't need re-pointing. Any other
  # llama_cpp_model keeps its own name as the alias.
  llama_cpp_alias = local.llama_cpp_model == "flash-next" ? "overnight-model" : local.llama_cpp_model

  # flash-next-specific GPU/CPU split, swept on the R9700: manually fixing
  # it beats llama.cpp's own device-fit heuristic (common_fit_params) here,
  # unlike on the old 3070 where manual pinning consistently OOM'd (see the
  # init_container comment below) -- the heuristic packs VRAM right up to
  # its limit (~97%), which measurably cost decode speed (14-19 tok/s)
  # versus a deliberately roomier split (--n-cpu-moe 30, ~80-95% VRAM
  # depending on quant, ~22-25 tok/s).
  #
  # Then --moe-cache-mib (0.7.0): a VRAM cache of the hot experts of the
  # CPU-resident layers. Moving more layers' experts to the CPU and giving
  # the freed VRAM to the cache beats keeping whole layers on the GPU
  # (UD-Q3_K_XL, real-text prompts, pp / tg tok/s):
  #   --n-cpu-moe 30, no cache   4k 489 / 20.5   34k 492 / 19.3   231k 316 / 8.9
  #   --n-cpu-moe 34, 4096 MiB   4k 478 / 27.7
  #   --n-cpu-moe 40, 10500 MiB  4k 449 / 29.4   34k 398 / 25.8   231k 286 / 12.5
  #   --n-cpu-moe 48, 18000 MiB  4k ~445 / 29.8 steady, but a cold first
  #                              request and only ~14GB of host RAM left
  # The cache is allocated before the ~1.8GB compute buffer, so leave that
  # much VRAM spare: 34/6000 and 40/13000 OOM'd at load. Not generalized to
  # other large MoEs in the map above (qwen3-235b doesn't fit this box at
  # all regardless; nothing else here is a comparable size) -- re-sweep
  # before reusing these values for a different model.
  llama_cpp_offload_args = local.llama_cpp_model == "flash-next" ? ["--n-gpu-layers", "99", "--n-cpu-moe", "40", "--moe-cache-mib", "10500"] : []
}

resource "kubernetes_ingress_v1" "llama_cpp_ryzen" {
  metadata {
    name      = "llama-cpp-ryzen"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }

  spec {
    rule {
      host = "llama-cpp-ryzen.${var.domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service_v1.llama_cpp_ryzen.metadata.0.name
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

resource "kubernetes_ingress_v1" "llama_cpp_ryzen_tls" {
  metadata {
    name      = "llama-cpp-ryzen-tls"
    namespace = kubernetes_namespace.namespace.metadata.0.name
    annotations = {
      "traefik.ingress.kubernetes.io/router.middlewares" = "cert-manager-redirect-https@kubernetescrd,cert-manager-hsts-headers@kubernetescrd"
    }
  }

  spec {
    rule {
      host = "llama-cpp-ryzen.${var.tls_domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service_v1.llama_cpp_ryzen.metadata.0.name
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

resource "kubernetes_service_v1" "llama_cpp_ryzen" {
  metadata {
    name      = "llama-cpp-ryzen"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    selector = {
      name = "llama-cpp-ryzen"
    }
    port {
      port        = 8080
      target_port = 8080
    }
  }
}

resource "kubernetes_deployment_v1" "llama_cpp_ryzen" {
  wait_for_rollout = false
  metadata {
    name      = "llama-cpp-ryzen"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = {
        name = "llama-cpp-ryzen"
      }
    }

    template {
      metadata {
        labels = {
          name = "llama-cpp-ryzen"
        }
        annotations = {
          prometheus_io_scrape = "true"
          prometheus_io_port   = "8080"
        }
      }
      spec {
        node_selector = {
          "amd.com/gpu.type"       = "r9700"
          "kubernetes.io/hostname" = "ryzen"
        }

        # On the pre-R9700 3070 (8GB VRAM), manually pinning layers/experts
        # to GPU/CPU (--n-gpu-layers/--cpu-moe/--override-tensor) consistently
        # OOM'd for the big MoEs here -- llama.cpp's own device-fit heuristic
        # (common_fit_params) was the only thing that got them to fit at all.
        # On the R9700 (32GB), that's flipped for flash-next: the heuristic
        # packs VRAM right up to ~97%, which measurably cost decode speed
        # versus a deliberately roomier manual split -- see
        # llama_cpp_offload_args above. Still relying on the heuristic (no
        # offload args) for the small qwen3-4b/1.7b/0.6b classification
        # models, where it's moot anyway: they fit entirely in VRAM either
        # way, so the heuristic just places 100% of layers on GPU.
        init_container {
          name  = "init-model"
          image = "curlimages/curl:8.11.1"
          # A single-stream curl against HF's CDN was observed stalling on
          # large files (Qwen3-235B download: ~0.75MB/s sustained despite a
          # fresh connection hitting 34MB/s in isolation -- looks like the
          # CDN throttles/resets long-lived single connections). aria2c with
          # multiple parallel range requests routes around that.
          command = ["sh", "-c", <<-EOT
            set -e
            apk add --no-cache aria2 >/dev/null
            for f in ${join(" ", local.llama_cpp_m.files)}; do
              test -f /models/$f && continue
              echo "downloading $f"
              aria2c -x8 -s8 -k1M -c --max-tries=20 --retry-wait=10 \
                --file-allocation=none --summary-interval=30 \
                -d /models -o "$f" \
                "https://huggingface.co/${local.llama_cpp_m.hf_path}/$f"
            done
          EOT
          ]
          security_context {
            run_as_user = 0
          }
          volume_mount {
            name       = "llama-cpp-models"
            mount_path = "/models"
          }
        }

        container {
          name              = "llama-cpp"
          image_pull_policy = "Always"
          image             = "ghcr.io/ggml-org/llama.cpp:server-rocm"

          args = concat([
            "-m", "/models/${local.llama_cpp_model_0}",
            "--alias", local.llama_cpp_alias,
            "--host", "0.0.0.0",
            "--port", "8080",

            "--ctx-size", tostring(local.llama_cpp_ctx_size),
            "--cache-type-k", "q8_0",
            "--cache-type-v", "q8_0",
            "--parallel", tostring(local.llama_cpp_parallel),

            "--load-mode", "none",
            "--cont-batching",
            "--jinja",
            "--metrics",
          ], local.llama_cpp_offload_args)

          port {
            container_port = 8080
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
            name       = "llama-cpp-models"
            mount_path = "/models"
          }
        }

        volume {
          name = "llama-cpp-models"
          host_path {
            path = "/var/lib/rancher/llama-cpp/models"
            type = "DirectoryOrCreate"
          }
        }
      }
    }
  }
}
