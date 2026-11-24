# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The node scaling operator.
job "operator" {
  id          = var.job_name
  name        = var.job_name
  type        = "service"
  region      = rigger.region
  datacenters = var.datacenters
  node_pool   = var.node_pool

  # Never on a node the operator created: such a node can be removed under
  # it, and an operator must not delete the machine it runs on.
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

  group "operator" {
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

    # And in different datacenters where there are several: when a
    # datacenter is lost, nodes are needed in the others, and an operator
    # that went with it would add none until it is placed again. A score,
    # not a rule: one datacenter is enough to run.
    dynamic "spread" {
      for_each = var.count > 1 ? [1] : []

      content {
        attribute = runtime("node.datacenter")
        weight    = 100
      }
    }

    network {
      port "metrics" {}

      # The join endpoint: the new nodes fetch and renew their certificates
      # here. A static port, so the firewall of the nodes can let it in.
      dynamic "port" {
        for_each = var.join_enabled ? ["join"] : []
        labels   = [port.value]

        content {
          static = var.join_port
        }
      }
    }

    # Without join_urls the nodes are told the instances of this service.
    dynamic "service" {
      for_each = var.join_enabled ? ["${var.job_name}-join"] : []

      content {
        name = service.value
        port = "join"

        # GET /v1/health answers 200 while the endpoint can issue
        # certificates. Its certificate comes from the node CA, which the
        # client does not know: the check does not verify it.
        check {
          type            = "http"
          protocol        = "https"
          path            = "/v1/health"
          tls_skip_verify = true
          interval        = "10s"
          timeout         = "2s"
        }
      }
    }

    task "operator" {
      driver = var.driver

      config {
        run_for = local.mock ? "87600h" : null
        image   = local.docker ? var.image : null
        ports   = local.docker ? (var.join_enabled ? ["metrics", "join"] : ["metrics"]) : null
        command = local.mock || local.docker ? null : var.binary
        args    = local.mock ? null : local.args
      }

      # The operator calls the API on the task API socket with its workload
      # identity; the ACL policy of the module is bound to this job. The
      # region comes from NORCA_REGION.
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
