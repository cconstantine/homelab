resource "kubernetes_config_map" "gpu_exporter_script_discrete" {
  metadata {
    name      = "gpu-exporter-script-discrete"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  data = {
    "exporter.py" = <<-PYTHON
      import time, logging
      from prometheus_client import start_http_server, Gauge
      import pynvml

      logging.basicConfig(level=logging.INFO)

      gpu_util     = Gauge('gpu_utilization',         'GPU utilization 0-1',        ['gpu'])
      gpu_mem_util = Gauge('gpu_memory_utilization',  'GPU memory utilization 0-1', ['gpu'])
      gpu_temp     = Gauge('gpu_temperature_celsius', 'GPU temperature',            ['gpu'])
      gpu_power    = Gauge('gpu_power_milliwatts',    'GPU power draw mW',          ['gpu'])
      gpu_fan      = Gauge('gpu_fan_speed_ratio',     'GPU fan speed 0-1',          ['gpu'])

      def update():
          pynvml.nvmlInit()
          for i in range(pynvml.nvmlDeviceGetCount()):
              h = pynvml.nvmlDeviceGetHandleByIndex(i)
              label = f"{i}:{pynvml.nvmlDeviceGetName(h)}"
              util = pynvml.nvmlDeviceGetUtilizationRates(h)
              gpu_util.labels(gpu=label).set(util.gpu / 100.0)
              gpu_mem_util.labels(gpu=label).set(util.memory / 100.0)
              gpu_temp.labels(gpu=label).set(pynvml.nvmlDeviceGetTemperature(h, pynvml.NVML_TEMPERATURE_GPU))
              try:
                  gpu_power.labels(gpu=label).set(pynvml.nvmlDeviceGetPowerUsage(h))
              except pynvml.NVMLError:
                  pass
              try:
                  gpu_fan.labels(gpu=label).set(pynvml.nvmlDeviceGetFanSpeed(h) / 100.0)
              except pynvml.NVMLError:
                  pass
          pynvml.nvmlShutdown()

      start_http_server(9835)
      logging.info('listening on :9835')
      while True:
          try:
              update()
          except Exception as e:
              logging.error(f'update: {e}')
          time.sleep(5)
      PYTHON
  }
}

resource "kubernetes_daemonset" "gpu_exporter_discrete" {
  metadata {
    name      = "gpu-exporter-discrete"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  wait_for_rollout = false
  spec {
    selector {
      match_labels = {
        app = "gpu-exporter-discrete"
      }
    }
    template {
      metadata {
        labels = {
          app = "gpu-exporter-discrete"
        }
        annotations = {
          prometheus_io_scrape = true
        }
      }
      spec {
        node_selector = {
          "nvidia.com/gpu.type" = "discrete"
        }

        toleration {
          key      = "nvidia.com/gpu"
          operator = "Exists"
          effect   = "NoSchedule"
        }

        runtime_class_name = "nvidia"

        host_network = true

        init_container {
          name    = "install-packages"
          image   = "python:3.11-slim"
          command = ["pip", "install", "--target=/packages", "--no-cache-dir", "--quiet", "pynvml", "prometheus_client"]

          volume_mount {
            name       = "packages"
            mount_path = "/packages"
          }
        }

        container {
          name = "gpu-exporter"

          resources {
            requests = {
              cpu    = "10m"
              memory = "48Mi"
            }
            limits = {
              memory = "80Mi"
            }
          }
          image   = "python:3.11-slim"
          command = ["python3", "/exporter/exporter.py"]

          env {
            name  = "PYTHONPATH"
            value = "/packages"
          }

          # Without these, the nvidia-container-runtime has no signal to inject
          # libnvidia-ml.so into the container (pynvml fails with "NVML Shared
          # Library Not Found"), even with runtime_class_name = "nvidia" set.
          # No nvidia.com/gpu resource request needed - this only reads NVML,
          # it doesn't need a device-plugin-allocated GPU slot.
          env {
            name  = "NVIDIA_VISIBLE_DEVICES"
            value = "all"
          }
          env {
            name  = "NVIDIA_DRIVER_CAPABILITIES"
            value = "all"
          }

          port {
            container_port = 9835
            protocol       = "TCP"
          }

          volume_mount {
            name       = "packages"
            mount_path = "/packages"
          }

          volume_mount {
            name       = "exporter-script"
            mount_path = "/exporter"
          }
        }

        volume {
          name = "packages"
          empty_dir {}
        }

        volume {
          name = "exporter-script"
          config_map {
            name = kubernetes_config_map.gpu_exporter_script_discrete.metadata.0.name
          }
        }
      }
    }
  }
}
