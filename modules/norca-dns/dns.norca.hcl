# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# norca-dns, the operator of the DNS records.
job "dns" {
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

  group "dns" {
    # One instance: a record is written by one writer at a time; a record
    # that changes while the instance is away is reconciled by the next one.
    count = 1

    task "dns" {
      driver = var.driver

      config {
        run_for = local.mock ? "87600h" : null
        image   = local.docker ? var.image : null
        command = local.mock || local.docker ? null : var.binary
        args    = local.mock ? null : local.args
      }

      # The CA of the https certificates of the DNS providers.
      dynamic "template" {
        for_each = var.zone_ca_cert != "" && !local.mock ? [var.zone_ca_cert] : []

        content {
          data        = "${trimspace(template.value)}\n"
          destination = "local/zone-ca.pem"
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
