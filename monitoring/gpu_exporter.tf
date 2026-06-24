resource "kubernetes_config_map" "gpu_exporter_script" {
  metadata {
    name      = "gpu-exporter-script"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  data = {
    "exporter.py" = <<-PYTHON
      import time, logging
      from prometheus_client import start_http_server, Gauge
      from jtop import jtop, JtopException

      logging.basicConfig(level=logging.INFO)

      gpu_util  = Gauge('jetson_gpu_utilization',     'GPU utilization 0-1')
      cpu_util  = Gauge('jetson_cpu_utilization',     'CPU utilization 0-1',  ['cpu'])
      temp      = Gauge('jetson_temperature_celsius', 'Temperature',           ['sensor'])
      power     = Gauge('jetson_power_milliwatts',    'Power consumption',     ['rail'])
      fan       = Gauge('jetson_fan',                 'Fan metrics',           ['fan', 'unit'])

      def update(jetson):
          stats = jetson.stats
          if 'GPU' in stats:
              gpu_util.set(stats['GPU'] / 100.0)
          for k, v in stats.items():
              if k.startswith('CPU') and isinstance(v, (int, float)):
                  cpu_util.labels(cpu=k).set(v / 100.0)
          for name, data in jetson.temperature.items():
              temp.labels(sensor=name).set(data['temp'])
          for name, data in jetson.power.items():
              if isinstance(data, dict):
                  power.labels(rail=name).set(data.get('power', data.get('cur', 0)))
          for name, data in jetson.fan.items():
              if not isinstance(data, dict):
                  continue
              if data.get('speed'):
                  fan.labels(fan=name, unit='speed_ratio').set(data['speed'][0] / 100.0)
              if data.get('rpm'):
                  fan.labels(fan=name, unit='rpm').set(data['rpm'][0])

      start_http_server(9835)
      logging.info('listening on :9835')
      while True:
          try:
              with jtop() as jetson:
                  logging.info('connected to jtop')
                  while jetson.ok():
                      try:
                          update(jetson)
                      except Exception as e:
                          logging.error(f'update: {e}')
                      time.sleep(5)
          except JtopException as e:
              logging.error(f'jtop: {e}, retry in 10s')
              time.sleep(10)
      PYTHON
  }
}

resource "kubernetes_daemonset" "gpu_exporter" {
  metadata {
    name      = "gpu-exporter"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  wait_for_rollout = false
  spec {
    selector {
      match_labels = {
        app = "gpu-exporter"
      }
    }
    template {
      metadata {
        labels = {
          app = "gpu-exporter"
        }
        annotations = {
          prometheus_io_scrape = true
        }
      }
      spec {
        node_selector = {
          "nvidia.com/gpu.type" = "tegra"
        }

        toleration {
          key      = "nvidia.com/gpu"
          operator = "Exists"
          effect   = "NoSchedule"
        }

        host_network = true

        init_container {
          name    = "install-packages"
          image   = "python:3.11-slim"
          command = ["sh", "-c", "touch /.dockerenv && pip install --target=/packages --no-cache-dir --quiet jetson-stats==4.3.2 prometheus_client"]

          volume_mount {
            name       = "packages"
            mount_path = "/packages"
          }
        }

        container {
          name    = "gpu-exporter"
          image   = "python:3.11-slim"
          command = ["python3", "/exporter/exporter.py"]

          env {
            name  = "PYTHONPATH"
            value = "/packages"
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

          volume_mount {
            name       = "jtop-sock"
            mount_path = "/run/jtop.sock"
          }
        }

        volume {
          name = "packages"
          empty_dir {}
        }

        volume {
          name = "exporter-script"
          config_map {
            name = kubernetes_config_map.gpu_exporter_script.metadata.0.name
          }
        }

        volume {
          name = "jtop-sock"
          host_path {
            path = "/run/jtop.sock"
            type = "Socket"
          }
        }
      }
    }
  }
}

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
          name    = "gpu-exporter"
          image   = "python:3.11-slim"
          command = ["python3", "/exporter/exporter.py"]

          env {
            name  = "PYTHONPATH"
            value = "/packages"
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
