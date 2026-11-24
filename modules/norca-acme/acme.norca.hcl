# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# norca-acme, the ACME controller of the certificate issuers.
job "acme" {
  id          = var.job_name
  name        = var.job_name
  type        = "service"
  region      = rigger.region
  datacenters = var.datacenters
  node_pool   = var.node_pool

  # Never on a node the node scaling operator created: such a node can be
  # removed under it.
  constraint {
    attribute = runtime("meta.norca.instance")
    operator  = "is_not_set"
  }

  group "acme" {
    # One instance: the answers of the HTTP-01 challenges are in the memory
    # of the instance that placed the order, and the edge router would send
    # a challenge to any instance. An order that is open when the instance
    # is lost is continued by the next one, from the status of the order.
    count = 1

    dynamic "network" {
      for_each = var.http01_enabled ? [1] : []

      content {
        port "http01" {}
      }
    }

    # The HTTP-01 challenge.
    dynamic "service" {
      for_each = var.http01_enabled ? [var.job_name] : []

      content {
        name     = service.value
        port     = "http01"
        provider = "nomad"
        tags     = local.http01_tags

        check {
          type     = "http"
          path     = "/healthz"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }

    task "acme" {
      driver = var.driver

      config {
        run_for = local.mock ? "87600h" : null
        image   = local.docker ? var.image : null
        ports   = local.docker && var.http01_enabled ? ["http01"] : null
        command = local.mock || local.docker ? null : var.binary
        args    = local.mock ? null : local.args
      }

      # The CA of the https certificate of the ACME directory, and that of
      # the DNS providers.
      dynamic "template" {
        for_each = local.ca_files

        content {
          data        = "${trimspace(template.value.cert)}\n"
          destination = template.value.file
          change_mode = "restart"
        }
      }

      # The operator calls the API on the task API socket with its workload
      # identity; the ACL policy of the module is bound to this job.
      identity {
        env = true
      }

      env {
        NORCA_ADDR = "unix://${runtime_env("NORCA_SECRETS_DIR")}/api.sock"
      }

      resources {
        cpu    = var.cpu
        memory = var.memory
      }
    }
  }
}
