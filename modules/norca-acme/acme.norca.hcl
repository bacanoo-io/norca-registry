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

  group "acme" {
    # One instance by default: the answers of the HTTP-01 challenges are in
    # the memory of the instance that placed the order, and the edge router
    # would send a challenge to any instance. An order that is open when the
    # instance is lost is continued by the next one, from the status of the
    # order. Several instances run with leader election (locals.hcl): one
    # works and answers, and the check on /readyz below tells which.
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

        # With leader election only the instance that leads answers the
        # challenges (review finding CON-6f): it alone answers /readyz with
        # 204, a standby with 503. The check makes the standbys unhealthy
        # in the catalog, so an edge router that looks up the healthy
        # instances routes to the leader only. It does not count for the
        # deployment (on_update): a standby fails it for as long as it is
        # one, and its allocation would never become healthy.
        dynamic "check" {
          for_each = local.leader_election ? [1] : []

          content {
            name      = "leading"
            type      = "http"
            path      = "/readyz"
            interval  = "5s"
            timeout   = "2s"
            on_update = "ignore"
          }
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
