# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# OpenObserve (AGPL-3.0, https://openobserve.ai): logs, metrics and traces
# of the cluster, in single mode (one group) or cluster mode (a group per
# node role). The nodes pull the official image; Norca does not ship it.
job "openobserve" {
  id          = local.job
  name        = local.job
  region      = rig.region
  datacenters = module.placement.datacenters
  node_pool   = module.placement.node_pool
  type        = "service"

  dynamic "constraint" {
    for_each = module.placement.constraints

    content {
      attribute = constraint.value.attribute
      operator  = constraint.value.operator
      value     = constraint.value.value
    }
  }

  dynamic "group" {
    for_each = local.groups
    labels   = [group.value.name]

    content {
      count = group.value.count

      # One ingester per node: they keep their WAL in the host volume.
      dynamic "constraint" {
        for_each = group.value.ingester_volume ? [1] : []

        content {
          operator = "distinct_hosts"
          value    = "true"
        }
      }

      # Single: one instance with its data on one node, so evictions are
      # refused, and a node drain moves it only when its deadline is
      # reached. Cluster: drains and evictions take down one instance of the
      # role at a time.
      disruption {
        min_healthy     = local.cluster ? null : "1"
        max_unavailable = local.cluster ? "1" : null
      }

      update {
        max_parallel      = 1
        health_check      = "checks"
        min_healthy_time  = "10s"
        healthy_deadline  = var.healthy_deadline
        progress_deadline = "0"
        auto_revert       = false
      }

      dynamic "migrate" {
        for_each = local.cluster ? [1] : []

        content {
          max_parallel     = 1
          health_check     = "checks"
          min_healthy_time = "10s"
          healthy_deadline = var.healthy_deadline
        }
      }

      # WAL (ingesters) and caches; the data itself is in S3.
      dynamic "ephemeral_disk" {
        for_each = local.cluster && !group.value.ingester_volume ? [1] : []

        content {
          sticky  = true
          migrate = group.value.role == "ingester"
          size    = var.cluster_disk_mb
        }
      }

      dynamic "volume" {
        for_each = local.cluster ? (group.value.ingester_volume ? [var.ingester_host_volume] : []) : [var.host_volume]
        labels   = ["data"]

        content {
          type      = "host"
          source    = volume.value
          read_only = false
        }
      }

      # Single: the ports mapped into the container. Cluster: host
      # networking (the task's network_mode), static ports for the users
      # and collectors on the routers, dynamic ports advertised to the other
      # nodes through NATS on the rest.
      network {
        port "http" {
          static       = group.value.router ? var.http_port : null
          to           = local.cluster ? null : 5080
          host_network = local.host_network
        }

        port "grpc" {
          static       = group.value.router ? var.grpc_port : null
          to           = local.cluster ? null : 5081
          host_network = local.host_network
        }
      }

      dynamic "secret_access" {
        for_each = group.value.bootstrap ? local.bootstrap_secret_paths : local.secret_paths

        content {
          path = secret_access.value
        }
      }

      # The UI, the API and OTLP/HTTP (/api/<organization>/v1/{logs,metrics,traces}).
      service {
        name     = group.value.router ? local.job : "${local.job}-${group.value.role}"
        provider = "nomad"
        port     = "http"
        tags     = local.cluster ? [group.value.role, local.scheme] : [local.scheme]

        # Norca's workload certificate (valid for <job>.service.<namespace>.norca),
        # used by OpenObserve itself (app mode, no sidecar). OpenObserve reads
        # it only at start: the client restarts the task after a renewal or a
        # CA rotation (not counted against the restart policy).
        dynamic "mtls" {
          for_each = local.mtls && group.value.router ? [1] : []

          content {
            mode        = "app"
            change_mode = "restart"
          }
        }

        # HTTP on /healthz without TLS. Norca's native HTTP checks verify
        # certificates against the system CAs and connect to the instance
        # address, which the workload certificate doesn't name, so with TLS
        # they are TCP checks.
        dynamic "check" {
          for_each = [
            { name = "startup", interval = "5s", timeout = "2s", startup_timeout = var.startup_timeout },
            { name = "readiness", interval = "10s", timeout = "3s", startup_timeout = null },
            { name = "liveness", interval = "15s", timeout = "3s", startup_timeout = null },
          ]

          content {
            name            = check.value.name
            role            = check.value.name
            type            = local.http ? "http" : "tcp"
            path            = local.http ? "/healthz" : null
            interval        = check.value.interval
            timeout         = check.value.timeout
            startup_timeout = check.value.startup_timeout

            dynamic "check_restart" {
              for_each = check.value.name == "liveness" ? [1] : []

              content {
                limit = 3
                grace = "60s"
              }
            }
          }
        }
      }

      # OTLP/gRPC (headers organization and stream-name), and in cluster mode
      # the gRPC of the node, registered by every role: with mTLS the
      # workload certificates of all nodes then carry
      # <job>-grpc.service.<namespace>.norca, the name they verify on
      # internal calls (ZO_GRPC_TLS_CERT_DOMAIN).
      service {
        name     = "${local.job}-grpc"
        provider = "nomad"
        port     = "grpc"
        tags     = local.cluster ? [group.value.role] : null

        dynamic "mtls" {
          for_each = local.mtls ? [1] : []

          content {
            mode        = "app"
            change_mode = "restart"
          }
        }
      }

      task "openobserve" {
        driver = "docker"

        config {
          image = module.placement.image
          # Cluster: host networking, a node advertises ZO_HTTP_ADDR and
          # ZO_GRPC_ADDR, the address it binds to, to the other nodes.
          network_mode = local.cluster ? "host" : null
          ports        = local.cluster ? null : ["http", "grpc"]
        }

        dynamic "volume_mount" {
          for_each = group.value.host_data ? ["data"] : []

          content {
            volume      = volume_mount.value
            destination = "/data"
          }
        }

        # The password of the root user (used when the root user is created).
        secret "root" {
          path = var.root_secret_path

          env {
            ZO_ROOT_USER_PASSWORD = "password"
          }
        }

        dynamic "secret" {
          for_each = local.cluster ? [1] : []
          labels   = ["postgres"]

          content {
            path = var.postgres_dsn_secret_path != "" ? var.postgres_dsn_secret_path : var.postgres_secret_path
            env  = var.postgres_dsn_secret_path != "" ? { ZO_META_POSTGRES_DSN = "dsn" } : { ZO_META_POSTGRES_PASSWORD = "password" }
          }
        }

        dynamic "secret" {
          for_each = local.cluster ? [var.s3_secret_path] : []
          labels   = ["s3"]

          content {
            path = secret.value

            env {
              ZO_S3_ACCESS_KEY = "access_key"
              ZO_S3_SECRET_KEY = "secret_key"
            }
          }
        }

        dynamic "secret" {
          for_each = local.cluster && var.nats_secret_path != "" ? [var.nats_secret_path] : []
          labels   = ["nats"]

          content {
            path = secret.value

            env {
              ZO_NATS_USER     = "username"
              ZO_NATS_PASSWORD = "password"
            }
          }
        }

        # PostgreSQL, NATS and S3: from the native catalog unless given. A
        # change (an instance moved) restarts the node.
        dynamic "template" {
          for_each = local.cluster ? [local.catalog_env] : []

          content {
            destination = "secrets/catalog.env"
            env         = true
            change_mode = "restart"
            splay       = "1m"
            data        = template.value
          }
        }

        dynamic "template" {
          for_each = var.tls_mode == "secret" ? ["cert", "key", "ca"] : []

          content {
            data        = "{{ with nomadSecret \"${var.tls_secret_path}\" }}{{ .${template.value} }}{{ end }}"
            destination = "secrets/tls/${template.value}.pem"
            perms       = "0400"
            change_mode = "restart"
          }
        }

        env = local.env[group.value.name]

        kill_timeout = "30s"

        resources {
          cpu    = group.value.cpu
          memory = group.value.memory
        }
      }

      # Idempotent setup after every start of the instance: the
      # organizations, the service account of the collectors and its token
      # in the secret store, the S3 bucket (cluster). The token is rotated
      # only when the stored credentials don't work (first run, or a lost
      # secret).
      dynamic "task" {
        for_each = group.value.bootstrap ? ["bootstrap"] : []
        labels   = [task.value]

        content {
          driver = "docker"

          lifecycle {
            hook    = "poststart"
            sidecar = false
          }

          config {
            image      = var.bootstrap_image
            entrypoint = ["/bin/sh", "/local/bootstrap.sh"]
          }

          # NORCA_TOKEN: the workload identity, which writes the ingest
          # secret through the task API (ACL policy of the module).
          identity {
            env = true
          }

          secret "root" {
            path = var.root_secret_path

            env {
              ROOT_PASSWORD = "password"
            }
          }

          # The stored ingest credentials, if any.
          secret "ingest" {
            path     = var.ingest_secret_path
            optional = true
            timeout  = "10s"

            env {
              INGEST_USERNAME = "username"
              INGEST_PASSWORD = "password"
            }
          }

          dynamic "secret" {
            for_each = local.bucket ? [var.s3_secret_path] : []
            labels   = ["s3"]

            content {
              path = secret.value

              env {
                AWS_ACCESS_KEY_ID     = "access_key"
                AWS_SECRET_ACCESS_KEY = "secret_key"
              }
            }
          }

          dynamic "template" {
            for_each = local.bucket ? [local.s3_env] : []

            content {
              destination = "secrets/s3.env"
              env         = true
              data        = template.value
            }
          }

          env {
            ROOT_EMAIL     = var.root_email
            OO_IP          = runtime_env("NORCA_IP_http")
            OO_PORT        = runtime_env("NORCA_HOST_PORT_http")
            OO_NAME        = "${local.job}.service.${runtime_env("NORCA_NAMESPACE")}.norca"
            ORGANIZATIONS  = join(" ", var.organizations)
            INGEST_ORG     = var.ingest_organization
            INGEST_ACCOUNT = var.ingest_service_account
            INGEST_PATH    = var.ingest_secret_path
          }

          template {
            destination = "local/bootstrap.sh"
            data        = local.bootstrap_script
          }

          restart {
            attempts = 3
            delay    = "30s"
            mode     = "fail"
          }

          resources {
            cpu    = 50
            memory = 32
          }
        }
      }
    }
  }
}
