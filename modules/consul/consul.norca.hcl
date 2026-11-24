# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Consul servers of one Norca region.
#
# Consul is licensed by HashiCorp under the Business Source License 1.1.
# Norca does not distribute it: the nodes pull the official image or
# download the official release archive. Nomad does not need Consul to run
# this job, so there is no circular dependency.
job "consul" {
  id          = local.job
  name        = local.job
  region      = rigger.region
  datacenters = length(var.datacenters) > 0 ? var.datacenters : null
  node_pool   = var.node_pool == "" ? null : var.node_pool
  type        = "service"

  group "servers" {
    count = var.server_count

    meta {
      consul_job = local.job
    }

    # One server per node: the agents use static ports on the host network.
    constraint {
      operator = "distinct_hosts"
      value    = "true"
    }

    # Only on the nodes reserved for Consul servers.
    dynamic "constraint" {
      for_each = var.server_node_meta != "" ? [var.server_node_meta] : []

      content {
        attribute = runtime("meta.${constraint.value}")
        value     = "true"
      }
    }

    # Spread the servers over the datacenters (one per availability zone):
    # losing a datacenter keeps the quorum.
    dynamic "spread" {
      for_each = var.datacenter_attribute != "" ? [var.datacenter_attribute] : []

      content {
        attribute = spread.value
        weight    = 100
      }
    }

    # At most one server per datacenter (fork feature).
    dynamic "separate" {
      for_each = var.datacenter_attribute != "" && var.datacenter_separate_required ? [var.datacenter_attribute] : []

      content {
        selector {
          consul_job = local.job
        }
        scope    = separate.value
        required = true
      }
    }

    # Drains and evictions take down one server at a time, so the Raft
    # quorum survives (fork feature).
    disruption {
      max_unavailable = "1"
    }

    # Rolling upgrade, one server at a time: the next server is replaced
    # only after the previous one passed its checks for min_healthy_time.
    # Servers keep their data on the host volume and do not leave the
    # cluster when they stop, so a restarted server rejoins as the same Raft
    # peer.
    update {
      max_parallel      = 1
      health_check      = "checks"
      min_healthy_time  = var.min_healthy_time
      healthy_deadline  = var.healthy_deadline
      progress_deadline = "0"
      auto_revert       = false
    }

    migrate {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = var.min_healthy_time
      healthy_deadline = var.healthy_deadline
    }

    # Raft log and snapshots. The scheduler only places servers on nodes
    # that have this host volume.
    dynamic "volume" {
      for_each = var.driver != "raw_exec" ? [var.server_host_volume] : []
      labels   = ["data"]

      content {
        type      = "host"
        source    = volume.value
        read_only = false
      }
    }

    network {
      dynamic "port" {
        for_each = local.server_port_order
        labels   = [port.value]

        content {
          static       = local.server_ports[port.value]
          host_network = local.host_network
        }
      }
    }

    # Server discovery: the retry_join lists of the servers and the clients
    # follow this group service. It is registered before the tasks start and
    # has no checks, so servers that have not formed the cluster yet are
    # found too.
    service {
      name     = "${local.job}-serf"
      port     = "serf_lan"
      provider = "nomad"
    }

    # The acl-setup task reads the secret ID of the metrics token.
    dynamic "secret_access" {
      for_each = var.metrics_enabled ? [var.metrics_token_secret_path] : []

      content {
        path = secret_access.value
      }
    }

    # Generates the gossip key, the CA, the server certificate and the ACL
    # tokens on the first start and stores them in Variables (see the
    # README), then waits until all servers are registered so that they
    # find each other on the first start.
    task "bootstrap" {
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      driver = var.bootstrap_driver

      config {
        command = "/bin/sh"
        args    = ["${runtime_env("NORCA_TASK_DIR")}/bootstrap.sh"]
      }

      # NORCA_TOKEN: the workload identity, used through the task API
      # socket.
      identity {
        env = true
      }

      env {
        NORCA_ADDR = "unix://${runtime_env("NORCA_SECRETS_DIR")}/api.sock"
        NORCA_BIN  = var.norca_binary
      }

      restart {
        attempts = 10
        interval = "30m"
        delay    = "15s"
        mode     = "delay"
      }

      template {
        destination = "local/bootstrap.sh"
        perms       = "0755"
        data        = local.bootstrap_script
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    task "server" {
      driver = var.driver
      # Exec tasks run as root: the rendered secrets are only readable by
      # root.
      user = var.driver == "exec" ? "root" : null

      # Docker: the host network, the agent is the node's local agent on
      # 127.0.0.1; the binary directly, not the image's entrypoint script,
      # so the agent runs as root in the container and reads the root-only
      # secrets.
      config {
        image        = local.docker ? local.image : null
        network_mode = local.docker ? "host" : null
        entrypoint   = local.docker ? ["consul"] : null
        command      = local.docker ? null : local.agent_command
        args         = local.agent_args
      }

      # The official release archive, unpacked into local/.
      dynamic "artifact" {
        for_each = local.artifacts

        content {
          source      = artifact.value
          destination = "local"

          dynamic "options" {
            for_each = var.download_checksum != "" ? [var.download_checksum] : []

            content {
              checksum = options.value
            }
          }
        }
      }

      dynamic "volume_mount" {
        for_each = var.driver != "raw_exec" ? ["data"] : []

        content {
          volume      = volume_mount.value
          destination = "/consul/data"
        }
      }

      kill_timeout = "30s"

      # The configuration. Changes (and new certificates) are applied with a
      # reload; servers stay Raft peers when they stop.
      template {
        destination   = "secrets/consul.d/consul.hcl"
        perms         = "0600"
        change_mode   = "signal"
        change_signal = "SIGHUP"
        data          = "${local.server_config}\n"
      }

      # The other servers, from the <job>-serf service. Consul reads
      # retry_join only at start, so a change needs no action.
      template {
        destination = "secrets/consul.d/join.json"
        perms       = "0600"
        change_mode = "noop"
        data        = local.join
      }

      dynamic "template" {
        for_each = local.tls ? ["ca_cert", "server_cert", "server_key"] : []

        content {
          destination   = "secrets/tls/${template.value}.pem"
          perms         = "0600"
          change_mode   = "signal"
          change_signal = "SIGHUP"
          data          = "{{ with nomadVar \"${local.server_var}\" }}{{ .${template.value}.Value }}{{ end }}"
        }
      }

      # The API service with the health check roles (fork feature): startup
      # until the RPC port is up, readiness while it answers (rolling
      # updates and drains wait for it), liveness restarts a hung agent.
      service {
        name     = local.job
        port     = local.api
        provider = "nomad"

        check {
          name            = "startup"
          role            = "startup"
          type            = "tcp"
          port            = "server"
          interval        = "5s"
          timeout         = "2s"
          startup_timeout = "5m"
        }

        check {
          name     = "readiness"
          role     = "readiness"
          type     = "tcp"
          port     = "server"
          interval = "10s"
          timeout  = "2s"
        }

        check {
          name     = "liveness"
          role     = "liveness"
          type     = "tcp"
          port     = local.api
          interval = "15s"
          timeout  = "3s"

          check_restart {
            limit = 3
          }
        }
      }

      # The HTTP port of the agent for the otel-collector module, which
      # scrapes the agent of its own node on 127.0.0.1 (the plain HTTP port
      # listens only there when TLS is on). No checks.
      dynamic "service" {
        for_each = var.metrics_enabled ? ["${local.job}-metrics"] : []

        content {
          name     = service.value
          port     = "http"
          provider = "nomad"
          tags     = ["metrics", "server"]
        }
      }

      resources {
        cpu    = var.server_resources.cpu
        memory = var.server_resources.memory
      }
    }

    # Creates the agent (and with snapshots the snapshot) ACL policy and
    # token with the secrets of the bootstrap task once the cluster has a
    # leader. Idempotent; it runs after every server start and exits.
    task "acl-setup" {
      lifecycle {
        hook    = "poststart"
        sidecar = false
      }

      driver = var.driver
      user   = var.driver == "exec" ? "root" : null

      config {
        image        = local.docker ? local.image : null
        network_mode = local.docker ? "host" : null
        entrypoint   = local.docker ? ["/bin/sh"] : null
        command      = local.docker ? null : "/bin/sh"
        args         = ["${runtime_env("NORCA_TASK_DIR")}/acl-setup.sh"]
      }

      dynamic "artifact" {
        for_each = local.artifacts

        content {
          source      = artifact.value
          destination = "local"

          dynamic "options" {
            for_each = var.download_checksum != "" ? [var.download_checksum] : []

            content {
              checksum = options.value
            }
          }
        }
      }

      env {
        CONSUL_BIN       = local.consul_bin
        CONSUL_HTTP_ADDR = "http://127.0.0.1:${var.port_http}"
      }

      restart {
        attempts = 10
        interval = "30m"
        delay    = "15s"
        mode     = "delay"
      }

      dynamic "template" {
        for_each = ["management_token", "agent_token", "snapshot_token"]

        content {
          destination = "secrets/${template.value}"
          perms       = "0600"
          data        = "{{ with nomadVar \"${local.server_var}\" }}{{ .${template.value}.Value | trimSpace }}{{ end }}"
        }
      }

      template {
        destination = "secrets/accessors.env"
        perms       = "0600"
        data        = <<-EOT
          {{- with nomadVar "${local.server_var}" }}
          AGENT_ACCESSOR={{ .agent_accessor.Value | trimSpace }}
          SNAPSHOT_ACCESSOR={{ .snapshot_accessor.Value | trimSpace }}
          {{- end }}
        EOT
      }

      template {
        destination = "local/agent-policy.hcl"
        data        = <<-EOT
          node_prefix "" {
            policy = "write"
          }
          service_prefix "" {
            policy = "read"
          }
        EOT
      }

      # The secret ID of the metrics token, from the built-in secret store.
      dynamic "secret" {
        for_each = var.metrics_enabled ? [var.metrics_token_secret_path] : []
        labels   = ["metrics"]

        content {
          path = secret.value

          file {
            destination = "secrets/metrics_token"
            format      = "raw:token"
          }
        }
      }

      dynamic "template" {
        for_each = var.metrics_enabled ? [1] : []

        content {
          destination = "local/metrics-policy.hcl"
          data        = <<-EOT
            agent_prefix "" {
              policy = "read"
            }
          EOT
        }
      }

      dynamic "template" {
        for_each = var.snapshot_enabled ? [1] : []

        content {
          destination = "local/snapshot-policy.hcl"
          data        = "acl = \"write\"\n"
        }
      }

      template {
        destination = "local/acl-setup.sh"
        perms       = "0755"
        data        = local.acl_setup_script
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
