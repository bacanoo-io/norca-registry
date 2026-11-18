# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# norca-provider: registers the node and load balancer providers of its
# configuration and serves the operators.
job "provider" {
  id          = var.job_name
  name        = var.job_name
  type        = "service"
  region      = rig.region
  datacenters = var.datacenters
  node_pool   = var.node_pool

  # Never on a node the node scaling operator created: such a node can be
  # removed under it.
  constraint {
    attribute = runtime("meta.norca.instance")
    operator  = "is_not_set"
  }

  group "provider" {
    # One instance: the providers of the configuration are registered once,
    # and a platform that keeps its load balancers in the process (tcpproxy)
    # must not run twice. A second instance would not be a standby either:
    # the registration has one endpoint, the heartbeat of the other instance
    # would hide that the endpoint is dead. When its node or its datacenter
    # is lost the job is placed again, in another of its datacenters.
    count = 1

    network {
      # The operators call the provider here: a static port, so the firewall
      # of the node can let them in.
      port "api" {
        static = var.port
      }
    }

    service {
      name     = var.job_name
      port     = "api"
      provider = "nomad"

      check {
        type     = "http"
        protocol = local.scheme
        path     = "/healthz"
        # The certificate may come from a CA the client does not know.
        tls_skip_verify = var.tls_enabled
        interval        = "10s"
        timeout         = "2s"
      }
    }

    task "provider" {
      driver = var.driver

      config {
        run_for = local.mock ? "87600h" : null
        image   = local.docker ? var.image : null
        ports   = local.docker ? ["api"] : null
        command = local.mock || local.docker ? null : var.binary
        args = local.mock ? null : [
          "-config", "${runtime_env("NORCA_TASK_DIR")}/providers.json",
          "-log-level", var.log_level,
          "-deregister-on-exit=${var.deregister_on_exit}",
        ]
      }

      # The provider registers on the task API socket with its workload
      # identity; the ACL policy of the module is bound to this job.
      identity {
        env = true
      }

      env {
        NORCA_ADDR = "unix://${runtime_env("NORCA_SECRETS_DIR")}/api.sock"
      }

      # The items of the job's Variable as environment variables, for the
      # env:NAME references of the configuration (tokens, credentials).
      dynamic "template" {
        for_each = var.secrets ? [local.variable_path] : []

        content {
          destination = "secrets/provider.env"
          env         = true
          change_mode = "restart"
          data        = <<-EOT
            {{- with nomadVar "${template.value}" }}
            {{- range $k, $item := . }}
            {{ $k }}={{ $item.Value | toJSON }}
            {{- end }}
            {{- end }}
          EOT
        }
      }

      dynamic "template" {
        for_each = var.tls_enabled ? [local.variable_path] : []

        content {
          data        = "{{ with nomadVar \"${template.value}\" }}{{ .tls_cert }}{{ end }}"
          destination = "secrets/tls.crt"
          change_mode = "restart"
        }
      }

      dynamic "template" {
        for_each = var.tls_enabled ? [local.variable_path] : []

        content {
          data        = "{{ with nomadVar \"${template.value}\" }}{{ .tls_key }}{{ end }}"
          destination = "secrets/tls.key"
          perms       = "0600"
          change_mode = "restart"
        }
      }

      # The configuration of norca-provider. It expands $${NAME} with the
      # environment of the task when it starts.
      template {
        destination = "local/providers.json"
        change_mode = "restart"
        data        = <<-EOT
          {
            "listen": ":$${NORCA_PORT_api}",%{if var.tls_enabled}
            "tls": { "cert": "$${NORCA_SECRETS_DIR}/tls.crt", "key": "$${NORCA_SECRETS_DIR}/tls.key" },%{endif}
            "advertise_url": ${jsonencode(local.advertise)},
            "heartbeat_interval": ${jsonencode(var.heartbeat_interval)},
            "providers": ${trimspace(var.providers)}
          }
        EOT
      }

      resources {
        cpu    = var.cpu
        memory = var.memory
      }
    }
  }
}
