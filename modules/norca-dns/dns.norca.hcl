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

  # Never on a node with the raw_exec driver (review finding JOG-19): a
  # raw_exec task or alloc-node-exec there runs as the user of the agent and
  # reads the secrets of every allocation of the node, the identity token of
  # this job and its bound ACL policies among them (allow_raw_exec_nodes).
  dynamic "constraint" {
    for_each = var.allow_raw_exec_nodes ? [] : [1]

    content {
      attribute = runtime("attr.driver.raw_exec")
      operator  = "is_not_set"
    }
  }

  group "dns" {
    # One instance by default: a record is written by one writer at a time;
    # a record that changes while the instance is away is reconciled by the
    # next one. Several instances run with leader election (locals.hcl), so
    # there is still one writer, and a standby takes over within the lease.
    count = var.count

    # The instances on different nodes: one node going does not take the
    # operator with it.
    dynamic "constraint" {
      for_each = var.count > 1 ? [1] : []

      content {
        operator = "distinct_hosts"
        value    = "true"
      }
    }

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
