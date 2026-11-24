# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Traefik Proxy (MIT): the edge router of the region. The entrypoints are
# the ports open to the outside; the routes come from the tags of the
# services in Norca's native catalog (Nomad provider) and from the static
# routes of the module (file provider), the certificates from the secret
# store.
job "traefik" {
  id          = local.job
  name        = local.job
  region      = rigger.region
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
    max_parallel     = 1
    min_healthy_time = "10s"
    healthy_deadline = "3m"
    auto_revert      = true
  }

  group "traefik" {
    count = var.job_type == "service" ? var.count : null

    # One instance per node: the entrypoints are static ports.
    dynamic "constraint" {
      for_each = var.job_type == "service" ? [1] : []

      content {
        operator = "distinct_hosts"
        value    = "true"
      }
    }

    network {
      mode = local.host ? null : "bridge"

      # The admin entrypoint (/ping, dashboard, metrics) on the default
      # network of the node, never on host_network.
      port "admin" {
        static = var.admin_port
        to     = local.host ? null : var.admin_port
      }

      dynamic "port" {
        for_each = var.entrypoints
        labels   = [local.labels[port.value.name]]

        content {
          static       = port.value.port
          to           = local.host ? null : port.value.port
          host_network = var.host_network == "" ? null : var.host_network
        }
      }
    }

    # The certificate secrets, read by the TLS template with the workload
    # identity (the submitter needs read-secret on them).
    dynamic "secret_access" {
      for_each = local.cert_secrets

      content {
        path = secret_access.value
      }
    }

    # The admin entrypoint: /ping is the health check of Traefik.
    service {
      name     = local.job
      port     = "admin"
      provider = "nomad"
      tags     = ["admin"]

      # Native mTLS: the workload certificate of Traefik for its backends;
      # the intentions name this service as the source.
      dynamic "mtls" {
        for_each = var.mtls ? [1] : []

        content {
          mode = "app"
        }
      }

      check {
        type     = "http"
        path     = "/ping"
        interval = "10s"
        timeout  = "2s"
      }
    }

    # One service per entrypoint.
    dynamic "service" {
      for_each = var.entrypoints

      content {
        name     = "${local.job}-${service.value.name}"
        port     = local.labels[service.value.name]
        provider = "nomad"
        tags     = ["entrypoint", service.value.protocol]
      }
    }

    task "traefik" {
      driver = "docker"

      config {
        image        = module.placement.image
        args         = ["--configfile=${runtime_env("NORCA_TASK_DIR")}/traefik.yml"]
        network_mode = local.host ? "host" : null
        ports        = local.host ? null : concat(["admin"], [for e in var.entrypoints : local.labels[e.name]])
      }

      # The workload identity (NORCA_TOKEN) reads the catalog through the
      # task API socket.
      identity {
        env = true
      }

      # The static configuration. A change restarts Traefik.
      template {
        destination = "local/traefik.yml"
        change_mode = "restart"
        data        = "${local.static_config}\n"
      }

      # TLS: Traefik watches the directory and applies a renewed
      # certificate without a restart.
      template {
        destination = "secrets/dynamic/tls.yml"
        change_mode = "noop"
        perms       = "0600"
        data        = "${local.tls_config}\n"
      }

      # The redirect to https as a router, so that it can leave out the
      # path of the ACME HTTP-01 challenge: a certificate authority asks for
      # /.well-known/acme-challenge/<token> over http, and the service that
      # answers it (norca-acme) routes that path by its catalog tags. The
      # priority keeps the redirect ahead of every other router of the
      # entrypoint, as the redirection of the entrypoint itself is.
      dynamic "template" {
        for_each = var.acme_challenge && length(local.redirects) > 0 ? [local.redirect_config] : []

        content {
          destination = "secrets/dynamic/redirect.yml"
          change_mode = "noop"
          data        = "${template.value}\n"
        }
      }

      # mTLS to the backends. The client renders it again when it renews
      # the certificate (the variables name the files on the client), and
      # Traefik applies it without a restart.
      dynamic "template" {
        for_each = length(var.mtls_backends) > 0 ? [local.mtls_config] : []

        content {
          destination = "secrets/dynamic/mtls.yml"
          change_mode = "noop"
          perms       = "0600"
          data        = "${template.value}\n"
        }
      }

      # The static routes of the module (dynamic_config) unchanged: the
      # delimiters of the template keep it from being interpolated.
      dynamic "template" {
        for_each = var.dynamic_config != "" ? [var.dynamic_config] : []

        content {
          destination     = "secrets/dynamic/routes.yml"
          change_mode     = "noop"
          left_delimiter  = "[%[%"
          right_delimiter = "%]%]"
          data            = "${trimsuffix(template.value, "\n")}\n"
        }
      }

      resources {
        cpu    = var.resources.cpu
        memory = var.resources.memory
      }
    }
  }
}
