# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Consul client agents of the datacenter, one per node (clients_enabled).
# Consul is the official HashiCorp release (BSL 1.1), not distributed by
# Norca. Workloads reach their local agent on 127.0.0.1.
job "clients" {
  enabled = var.clients_enabled

  id          = "${local.job}-clients"
  name        = "${local.job}-clients"
  region      = rigger.region
  datacenters = length(var.datacenters) > 0 ? var.datacenters : null
  node_pool   = var.node_pool == "" ? null : var.node_pool
  type        = "system"

  group "client" {
    # Not on the server nodes: a server is the local agent of its node.
    dynamic "constraint" {
      for_each = var.server_node_meta != "" ? [var.server_node_meta] : []

      content {
        attribute = runtime("meta.${constraint.value}")
        operator  = "!="
        value     = "true"
      }
    }

    update {
      max_parallel     = 1
      min_healthy_time = "10s"
    }

    # The agent state (node ID, check state) survives restarts on the node.
    ephemeral_disk {
      sticky = true
      size   = 300
    }

    network {
      dynamic "port" {
        for_each = local.client_port_order
        labels   = [port.value]

        content {
          static       = local.server_ports[port.value]
          host_network = local.host_network
        }
      }
    }

    task "client" {
      driver = var.driver
      user   = var.driver == "exec" ? "root" : null

      config {
        image        = local.docker ? local.image : null
        network_mode = local.docker ? "host" : null
        entrypoint   = local.docker ? ["consul"] : null
        command      = local.docker ? null : local.agent_command
        args         = local.agent_args
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

      kill_timeout = "30s"

      # The configuration, from the Variable written by the servers'
      # bootstrap task (the task waits until it exists).
      template {
        destination   = "secrets/consul.d/consul.hcl"
        perms         = "0600"
        change_mode   = "signal"
        change_signal = "SIGHUP"
        data          = "${local.client_config}\n"
      }

      # The servers, from the <job>-serf service. retry_join is read only at
      # start: a client that started before the servers were registered is
      # restarted (with a random delay) when the list changes.
      template {
        destination = "secrets/consul.d/join.json"
        perms       = "0600"
        change_mode = "restart"
        splay       = "2m"
        data        = local.join
      }

      dynamic "template" {
        for_each = local.tls ? [local.client_var] : []

        content {
          destination   = "secrets/tls/ca_cert.pem"
          perms         = "0600"
          change_mode   = "signal"
          change_signal = "SIGHUP"
          data          = "{{ with nomadVar \"${template.value}\" }}{{ .ca_cert.Value }}{{ end }}"
        }
      }

      service {
        name     = "${local.job}-client"
        port     = "serf_lan"
        provider = "nomad"

        check {
          name     = "liveness"
          role     = "liveness"
          type     = "tcp"
          port     = "serf_lan"
          interval = "15s"
          timeout  = "3s"

          check_restart {
            limit = 3
          }
        }
      }

      # The HTTP port of the agent for the otel-collector module (scraped on
      # 127.0.0.1 of the node). No checks.
      dynamic "service" {
        for_each = var.metrics_enabled ? ["${local.job}-metrics"] : []

        content {
          name     = service.value
          port     = "http"
          provider = "nomad"
          tags     = ["metrics", "client"]
        }
      }

      resources {
        cpu    = var.client_resources.cpu
        memory = var.client_resources.memory
      }
    }
  }
}
