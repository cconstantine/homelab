# llama.cpp server on ryzen, replacing ollama-ryzen (scaled to 0 in
# ollama.tf). Uses the upstream ggml-org CUDA image since ryzen is a plain
# x86_64 + discrete-GPU host (no Jetson/L4T quirks).

locals {
  # Which model llama-cpp-ryzen serves. Flip llama_cpp_model and re-apply.
  #
  #   flash-next     Qwen3.8-Flash-Next UD-Q2_K_XL (~79GB, ~4B active, hybrid
  #                  attention). Hardware-matched: tiny active expert set,
  #                  fits ryzen's 96GB RAM well enough, ~25 tok/s with the
  #                  full 3070. Good general/agentic model, but massively
  #                  overkill (and too slow, ~10-25 tok/s, single stream
  #                  only) for high-volume short-text classification.
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
      hf_path = "unsloth/Qwen3.8-Flash-Next-GGUF/resolve/main/UD-Q2_K_XL"
      files   = [for i in range(1, 4) : "Qwen3.8-Flash-Next-UD-Q2_K_XL-0000${i}-of-00003.gguf"]
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
          "nvidia.com/gpu.type"    = "discrete"
          "kubernetes.io/hostname" = "ryzen"
        }

        runtime_class_name = "nvidia"

        # Deliberately *not* passing --n-gpu-layers/--cpu-moe/--override-tensor
        # here: any of those disables llama.cpp's own device-fit heuristic
        # (common_fit_params). For the big MoEs (flash-next, qwen3-235b) that
        # heuristic is the only thing that got them to fit in the 3070's 8GB
        # VRAM at all -- manually pinning layers/experts to GPU/CPU
        # consistently OOM'd. For the small qwen3-4b/1.7b/0.6b classification
        # models it's moot: they fit entirely in VRAM either way, so the
        # heuristic just places 100% of layers on GPU automatically.
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
          image             = "ghcr.io/ggml-org/llama.cpp:server-cuda"

          args = [
            "-m", "/models/${local.llama_cpp_model_0}",
            "--alias", local.llama_cpp_model,
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
          ]

          port {
            container_port = 8080
          }

          env {
            name  = "NVIDIA_VISIBLE_DEVICES"
            value = "all"
          }
          env {
            name  = "NVIDIA_DRIVER_CAPABILITIES"
            value = "all"
          }

          resources {
            limits = {
              "nvidia.com/gpu" = "1"
            }
            requests = {
              "nvidia.com/gpu" = "1"
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
