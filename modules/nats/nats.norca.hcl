# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The NATS cluster of one Norca region. In a multi-cloud setup the module
# runs once per region; the gateways join the clusters into a supercluster
# over the VPN.
job "nats" {
  id          = local.job
  name        = local.job
  region      = rig.region
  datacenters = length(var.datacenters) > 0 ? var.datacenters : null
  node_pool   = var.node_pool == "" ? null : var.node_pool
  type        = "service"

  group "nats" {
    count = var.count

    meta {
      nats_job = local.job
    }

    # One server per node.
    dynamic "constraint" {
      for_each = var.distinct_hosts ? [1] : []

      content {
        operator = "distinct_hosts"
        value    = "true"
      }
    }

    # Spread the servers over topology domains (fork feature).
    dynamic "separate" {
      for_each = var.separate_scope != "" ? [var.separate_scope] : []

      content {
        selector {
          nats_job = local.job
        }
        scope    = separate.value
        required = var.separate_required
      }
    }

    # Drains and evictions take down at most this many servers at a time, so
    # the JetStream Raft groups keep their majority (fork feature).
    dynamic "disruption" {
      for_each = var.disruption_max_unavailable != "" ? [var.disruption_max_unavailable] : []

      content {
        max_unavailable = disruption.value
      }
    }

    # Rolling updates one server at a time; a server counts as healthy only
    # when its readiness check (/healthz: JetStream current) passes.
    update {
      max_parallel      = 1
      health_check      = "checks"
      min_healthy_time  = "10s"
      healthy_deadline  = var.healthy_deadline
      progress_deadline = "0"
      auto_revert       = false
    }

    migrate {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "10s"
      healthy_deadline = var.healthy_deadline
    }

    # JetStream data in alloc/data: kept when the allocation is replaced on
    # the same node (sticky) and copied to a new node if the old one is
    # still reachable (migrate). Not a durable volume: replication (R3
    # streams) protects against losing a node.
    dynamic "ephemeral_disk" {
      for_each = var.storage == "ephemeral_disk" ? [var.ephemeral_disk_size] : []

      content {
        sticky  = true
        migrate = true
        size    = ephemeral_disk.value
      }
    }

    dynamic "volume" {
      for_each = var.storage == "host_volume" ? [var.host_volume] : []
      labels   = ["jetstream"]

      content {
        type      = "host"
        source    = volume.value
        read_only = false
      }
    }

    network {
      dynamic "port" {
        for_each = local.ports
        labels   = [port.value.label]

        content {
          static       = port.value.number > 0 ? port.value.number : null
          host_network = local.host_network
        }
      }

      dynamic "port" {
        for_each = var.metrics_enabled ? ["metrics"] : []
        labels   = [port.value]

        content {
          static       = var.metrics_port > 0 ? var.metrics_port : null
          to           = 7777
          host_network = local.host_network
        }
      }
    }

    # The token (and the CA) of the leaf node on the system bus of the Norca
    # servers.
    dynamic "secret_access" {
      for_each = var.norca_bus_leaf ? [var.norca_bus_secret] : []

      content {
        path = secret_access.value
      }
    }

    # The passwords of the users (auth_mode = "userpass"), item password of
    # one secret per user.
    dynamic "secret_access" {
      for_each = local.userpass ? var.users : []

      content {
        path = "${var.users_secret_prefix}/${secret_access.value.name}"
      }
    }

    # The route addresses of the servers. A group service is registered
    # before the tasks start, so the servers find each other on their first
    # start; it has no checks, so servers that are not ready yet are found
    # too.
    dynamic "service" {
      for_each = concat(local.routes ? ["cluster"] : [], var.gateway_enabled ? ["gateway"] : [])

      content {
        name     = "${local.job}-${service.value}"
        port     = service.value
        provider = "nomad"
      }
    }

    task "nats" {
      driver = var.driver

      config {
        image   = local.docker ? var.image : null
        command = local.docker ? null : var.binary
        args    = ["--config", "${runtime_env("NORCA_SECRETS_DIR")}/nats.conf"]
        ports   = local.docker ? [for p in local.ports : p.label] : null
      }

      dynamic "artifact" {
        for_each = !local.docker && var.artifact_url != "" ? [var.artifact_url] : []

        content {
          source = artifact.value

          dynamic "options" {
            for_each = var.artifact_checksum != "" ? [var.artifact_checksum] : []

            content {
              checksum = options.value
            }
          }
        }
      }

      dynamic "volume_mount" {
        for_each = var.storage == "host_volume" ? ["jetstream"] : []

        content {
          volume      = volume_mount.value
          destination = "/data"
        }
      }

      # Lame duck mode: stop accepting clients, move them to the other
      # servers, then shut down.
      kill_signal  = "SIGUSR2"
      kill_timeout = var.kill_timeout

      # The configuration. Routes follow the <job>-cluster service; changes
      # (and new certificates or credentials) are applied with a reload.
      template {
        destination   = "secrets/nats.conf"
        perms         = "0600"
        change_mode   = "signal"
        change_signal = "SIGHUP"
        data          = "${local.config}\n"
      }

      # The CA of the Norca servers, item ca of the secret norca_bus_secret:
      # the leaf node verifies the bus with it.
      dynamic "template" {
        for_each = var.norca_bus_leaf && var.norca_bus_tls ? [var.norca_bus_secret] : []

        content {
          destination   = "secrets/norca_bus/ca.pem"
          perms         = "0600"
          change_mode   = "signal"
          change_signal = "SIGHUP"
          data          = "{{ with (nomadSecret \"${template.value}\").ca }}{{ . }}{{ else }}{{ sprig_fail \"the secret ${template.value} has no item ca\" }}{{ end }}"
        }
      }

      # TLS material from the secrets Variable (items tls_ca, tls_cert,
      # tls_key). The task does not start until the Variable exists.
      dynamic "template" {
        for_each = var.tls_enabled ? ["ca", "cert", "key"] : []

        content {
          destination   = "secrets/tls/${template.value}.pem"
          perms         = "0600"
          change_mode   = "signal"
          change_signal = "SIGHUP"
          data          = "{{ with nomadVar \"${local.secrets}\" }}{{ .tls_${template.value} }}{{ end }}"
        }
      }

      # Client service with the health check roles (fork feature): startup
      # until the server runs with JetStream, readiness while JetStream is
      # current (deployments and drains wait for it), liveness restarts a
      # hung server.
      service {
        name     = local.job
        port     = "client"
        provider = "nomad"

        check {
          name            = "startup"
          role            = "startup"
          type            = "http"
          port            = "monitor"
          path            = local.light
          interval        = "5s"
          timeout         = "2s"
          startup_timeout = var.startup_timeout
        }

        check {
          name     = "readiness"
          role     = "readiness"
          type     = "http"
          port     = "monitor"
          path     = "/healthz"
          interval = "10s"
          timeout  = "3s"
        }

        check {
          name     = "liveness"
          role     = "liveness"
          type     = "http"
          port     = "monitor"
          path     = local.light
          interval = "15s"
          timeout  = "3s"

          check_restart {
            limit = 3
          }
        }
      }

      service {
        name     = "${local.job}-monitor"
        port     = "monitor"
        provider = "nomad"
      }

      dynamic "service" {
        for_each = var.leafnodes_enabled ? ["${local.job}-leafnode"] : []

        content {
          name     = service.value
          port     = "leafnode"
          provider = "nomad"
        }
      }

      resources {
        cpu    = var.resources.cpu
        memory = var.resources.memory
      }
    }

    # The Prometheus exporter of the server: it polls the monitoring port of
    # the server of its allocation and serves /metrics on the metrics port,
    # registered as <job>-metrics for the otel-collector module.
    dynamic "task" {
      for_each = var.metrics_enabled ? ["metrics"] : []
      labels   = [task.value]

      content {
        driver = "docker"

        lifecycle {
          hook    = "poststart"
          sidecar = true
        }

        config {
          image = var.metrics_image
          ports = ["metrics"]
          args = concat(
            ["-port", "7777", "-addr", "0.0.0.0", "-use_internal_server_name", "-varz", "-connz", "-routez", "-subz", "-healthz"],
            var.jetstream_enabled ? ["-jsz=all"] : [],
            var.gateway_enabled ? ["-gatewayz"] : [],
            var.leafnodes_enabled ? ["-leafz"] : [],
            ["http://${runtime_env("NORCA_ADDR_monitor")}"],
          )
        }

        service {
          name     = "${local.job}-metrics"
          port     = "metrics"
          provider = "nomad"
          # No checks: an exporter problem must not hold up the deployments
          # and drains of the servers.
          tags = ["metrics"]
        }

        resources {
          cpu    = var.metrics_resources.cpu
          memory = var.metrics_resources.memory
        }
      }
    }
  }
}
