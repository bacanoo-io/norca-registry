# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The OpenTelemetry Collector (contrib distribution, Apache-2.0): one
# collector on every node, which collects the metrics of the node and of
# the platform components on it, receives OTLP from the applications of
# the node, and exports everything to OpenObserve.
job "otel-collector" {
  id          = local.job
  name        = local.job
  region      = rigger.region
  datacenters = module.placement.datacenters
  node_pool   = module.placement.node_pool
  type        = "system"

  dynamic "constraint" {
    for_each = module.placement.constraints

    content {
      attribute = constraint.value.attribute
      operator  = constraint.value.operator
      value     = constraint.value.value
    }
  }

  update {
    max_parallel     = 1
    min_healthy_time = "10s"
  }

  group "collector" {
    # Host networking (the task's network_mode): the host's network
    # interfaces for the host metrics, the local agent on 127.0.0.1, the
    # OTLP ports on the node address.
    network {
      dynamic "port" {
        for_each = var.otlp_enabled ? { otlp_grpc = var.otlp_grpc_port, otlp_http = var.otlp_http_port } : {}
        labels   = [port.key]

        content {
          static       = port.value
          host_network = var.host_network == "" ? null : var.host_network
        }
      }

      port "health" {}

      dynamic "port" {
        for_each = var.self_metrics_enabled ? ["telemetry"] : []
        labels   = [port.value]

        content {}
      }
    }

    # The host's root directory, read-only, for the host metrics.
    dynamic "volume" {
      for_each = local.hostfs ? [var.host_root_volume] : []
      labels   = ["hostfs"]

      content {
        type      = "host"
        source    = volume.value
        read_only = true
      }
    }

    dynamic "secret_access" {
      for_each = local.secret_paths

      content {
        path = secret_access.value
      }
    }

    service {
      name     = local.job
      provider = "nomad"
      port     = "health"

      # The workload identity of the collector: a certificate and the trust
      # bundle of the region in secrets/mtls, with which it verifies
      # OpenObserve (and PostgreSQL with postgres_tls = "verify-ca"). The
      # collector serves no TLS on this port. It reads the bundle (ca_file)
      # only when it loads its configuration: the client reloads it
      # (SIGHUP) when a new CA joins the bundle.
      dynamic "mtls" {
        for_each = local.identity ? [1] : []

        content {
          mode          = "app"
          change_mode   = "signal"
          change_signal = "SIGHUP"
          change_on     = "bundle"
        }
      }

      check {
        name            = "startup"
        role            = "startup"
        type            = "http"
        path            = "/"
        interval        = "5s"
        timeout         = "2s"
        startup_timeout = "2m"
      }

      check {
        name     = "liveness"
        role     = "liveness"
        type     = "http"
        path     = "/"
        interval = "15s"
        timeout  = "3s"

        check_restart {
          limit = 3
          grace = "30s"
        }
      }
    }

    # OTLP of the node for the applications (they send to the collector of
    # their own node: ${attr.unique.network.ip-address} and the OTLP ports).
    dynamic "service" {
      for_each = var.otlp_enabled ? ["grpc", "http"] : []

      content {
        name     = "${local.job}-otlp-${service.value}"
        provider = "nomad"
        port     = "otlp_${service.value}"
        tags     = ["otlp", service.value]
      }
    }

    task "collector" {
      driver = "docker"

      config {
        image        = module.placement.image
        network_mode = "host"
        args         = ["--config", "/local/config.yaml"]
      }

      # secrets/norca_token: the workload identity, with which the
      # Prometheus receiver reads the catalog (nomad_sd_configs).
      identity {
        file = true
      }

      dynamic "volume_mount" {
        for_each = local.hostfs ? ["hostfs"] : []

        content {
          volume           = volume_mount.value
          destination      = "/hostfs"
          read_only        = true
          propagation_mode = "host-to-task"
        }
      }

      # The ingest credentials of OpenObserve, written by the bootstrap task
      # of the openobserve module. The collector waits for them.
      secret "ingest" {
        path    = var.ingest_secret_path
        timeout = "15m"

        env {
          OO_USERNAME = "username"
          OO_PASSWORD = "password"
          OO_ORG      = var.openobserve_organization == "" ? "organization" : null
        }
      }

      dynamic "secret" {
        for_each = var.forgejo_metrics_enabled ? [var.forgejo_metrics_secret_path] : []
        labels   = ["forgejo"]

        content {
          path     = secret.value
          optional = true
          timeout  = "10s"

          env {
            FORGEJO_METRICS_TOKEN = "token"
          }
        }
      }

      dynamic "secret" {
        for_each = var.consul_metrics_enabled ? [var.consul_metrics_secret_path] : []
        labels   = ["consul"]

        content {
          path     = secret.value
          optional = true
          timeout  = "10s"

          env {
            CONSUL_METRICS_TOKEN = "token"
          }
        }
      }

      dynamic "secret" {
        for_each = var.postgres_metrics_enabled ? [var.postgres_secret_path] : []
        labels   = ["postgres"]

        content {
          path     = secret.value
          optional = true
          timeout  = "10s"

          env {
            PG_MONITORING_PASSWORD = "password"
          }
        }
      }

      dynamic "template" {
        for_each = local.ca_files

        content {
          data        = "{{ with nomadSecret \"${template.value.path}\" }}{{ .ca }}{{ end }}"
          destination = template.value.file
          uid         = 10001
          gid         = 10001
          perms       = "0400"
          change_mode = "restart"
        }
      }

      env = merge(
        {
          NODE_ID        = runtime("node.unique.id")
          NODE_NAME      = runtime("node.unique.name")
          OO_SERVER_NAME = local.server_name
        },
        var.openobserve_organization != "" ? { OO_ORG = var.openobserve_organization } : {},
      )

      # The configuration; a change (an instance of OpenObserve or
      # PostgreSQL moved) is applied with a reload (SIGHUP).
      template {
        destination   = "local/config.yaml"
        change_mode   = "signal"
        change_signal = "SIGHUP"
        data          = "${local.config}\n"
      }

      kill_timeout = "20s"

      resources {
        cpu    = var.resources.cpu
        memory = var.resources.memory
      }
    }
  }
}
