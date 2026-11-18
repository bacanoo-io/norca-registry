# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The mTLS gateway of the region: a group with a service in gateway mode,
# whose Envoy task the servers inject, or the module defines
# (envoy_task_enabled).
job "gateway" {
  id   = var.job_name
  name = var.job_name
  # Always the default namespace: upstreams of other regions look for
  # gateways only there.
  namespace   = "default"
  region      = rig.region
  datacenters = module.placement.datacenters
  node_pool   = module.placement.node_pool
  type        = var.job_type

  dynamic "constraint" {
    for_each = module.placement.constraints

    content {
      attribute = constraint.value.attribute
      operator  = constraint.value.operator
      value     = constraint.value.value
    }
  }

  update {
    max_parallel     = var.update_max_parallel
    min_healthy_time = local.system ? null : "10s"
  }

  group "gateway" {
    count = local.system ? null : var.count

    network {
      mode = var.network_mode

      port "mtls" {
        static       = var.port
        to           = local.bridge ? var.port : null
        host_network = var.host_network == "" ? null : var.host_network
      }

      dynamic "port" {
        for_each = var.metrics_enabled ? ["metrics"] : []
        labels   = [port.value]

        content {
          static       = var.metrics_port > 0 ? var.metrics_port : null
          host_network = var.host_network == "" ? null : var.host_network
        }
      }

      dynamic "port" {
        for_each = var.metrics_enabled ? ["envoy_admin"] : []
        labels   = [port.value]

        content {}
      }
    }

    dynamic "constraint" {
      for_each = !local.system && var.distinct_hosts ? [1] : []

      content {
        operator = "distinct_hosts"
        value    = "true"
      }
    }

    service {
      name     = var.service_name
      port     = "mtls"
      provider = "nomad"
      tags     = length(var.service_tags) > 0 ? var.service_tags : null

      mtls {
        mode = "gateway"
      }
    }

    dynamic "service" {
      for_each = var.metrics_enabled ? ["${var.service_name}-metrics"] : []

      content {
        name     = service.value
        port     = "metrics"
        provider = "nomad"
        tags     = ["metrics"]
      }
    }

    dynamic "task" {
      for_each = var.envoy_task_enabled ? ["envoy"] : []
      labels   = [task.value]

      content {
        kind   = "mtls-gateway:${var.service_name}"
        driver = var.envoy_driver

        config {
          image        = local.container ? (var.envoy_image != "" ? var.envoy_image : runtime("meta.norca.mtls.envoy_image")) : null
          command      = local.container ? null : var.envoy_binary
          args         = local.envoy_args
          network_mode = local.container && !local.bridge ? "host" : null
        }

        constraint {
          attribute = runtime("attr.norca.version")
          operator  = "is_set"
        }

        shutdown_delay = "5s"

        logs {
          max_files     = 2
          max_file_size = 2
        }

        resources {
          cpu    = var.envoy_resources.cpu
          memory = var.envoy_resources.memory
        }
      }
    }
  }
}
