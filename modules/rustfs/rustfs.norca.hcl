# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# RustFS, an S3-compatible object store (Apache-2.0, https://rustfs.com),
# as the store of the Norca backups. The nodes pull the official image;
# Norca does not ship it. Keep the backups of a cluster outside the cluster
# they protect: run this job in another region or cluster than the servers
# it backs up, or use an external S3 store in production.
job "rustfs" {
  id          = local.job
  name        = local.job
  region      = rigger.region
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

  group "rustfs" {
    count = local.distributed ? length(var.nodes) : 1

    # One server on each node of the endpoint list.
    dynamic "constraint" {
      for_each = local.distributed ? [join(",", var.nodes)] : []

      content {
        attribute = var.node_address_attribute
        operator  = "set_contains_any"
        value     = constraint.value
      }
    }

    dynamic "constraint" {
      for_each = local.distributed ? [1] : []

      content {
        operator = "distinct_hosts"
        value    = "true"
      }
    }

    # Distributed: drains and evictions take down one server at a time, so
    # the erasure sets keep their quorum. A single instance: evictions
    # (norca alloc stop -respect-disruption) are refused, and a node drain
    # moves it only when its deadline is reached.
    disruption {
      max_unavailable = local.distributed ? "1" : null
      min_healthy     = local.distributed ? null : "1"
    }

    # One server at a time; a server counts as healthy when its readiness
    # check passes.
    update {
      max_parallel      = 1
      health_check      = "checks"
      min_healthy_time  = "10s"
      healthy_deadline  = var.healthy_deadline
      progress_deadline = "0"
      auto_revert       = false
    }

    migrate {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "10s"
      healthy_deadline = var.healthy_deadline
    }

    # Static ports on the node, the same inside the container: the Norca
    # servers (and the other RustFS servers) reach the S3 API at
    # http://<node address>:<s3_port>.
    network {
      port "s3" {
        static       = var.s3_port
        to           = var.s3_port
        host_network = var.host_network == "" ? null : var.host_network
      }

      dynamic "port" {
        for_each = var.console_enabled ? ["console"] : []
        labels   = [port.value]

        content {
          static       = var.console_port
          to           = var.console_port
          host_network = var.host_network == "" ? null : var.host_network
        }
      }
    }

    volume "data" {
      type      = "host"
      source    = var.host_volume
      read_only = false
    }

    # The tasks read only the secret with the root credentials.
    secret_access {
      path = var.secret_path
    }

    service {
      name     = local.job
      provider = "nomad"
      port     = "s3"

      check {
        name            = "startup"
        role            = "startup"
        type            = "http"
        path            = "/health/live"
        interval        = "5s"
        timeout         = "2s"
        startup_timeout = var.startup_timeout
      }

      # Ready when the server can serve requests (storage, IAM and lock
      # quorum); during startup it answers 503.
      check {
        name     = "readiness"
        role     = "readiness"
        type     = "http"
        path     = "/health/ready"
        interval = "10s"
        timeout  = "3s"
      }

      check {
        name     = "liveness"
        role     = "liveness"
        type     = "http"
        path     = "/health/live"
        interval = "15s"
        timeout  = "3s"
      }
    }

    dynamic "service" {
      for_each = var.console_enabled ? ["${local.job}-console"] : []

      content {
        name     = service.value
        provider = "nomad"
        port     = "console"

        check {
          name     = "readiness"
          role     = "readiness"
          type     = "http"
          path     = "/rustfs/console/health"
          interval = "15s"
          timeout  = "3s"
        }
      }
    }

    task "rustfs" {
      driver = "docker"

      config {
        image = module.placement.image
        ports = var.console_enabled ? ["s3", "console"] : ["s3"]
      }

      user = var.user == "" ? null : var.user

      volume_mount {
        volume      = "data"
        destination = "/data"
      }

      # The root credentials, from the built-in secret store.
      secret "root" {
        path = var.secret_path

        env {
          RUSTFS_ACCESS_KEY = "access_key"
          RUSTFS_SECRET_KEY = "secret_key"
        }
      }

      env = local.env

      kill_timeout = "30s"

      resources {
        cpu    = var.resources.cpu
        memory = var.resources.memory
      }
    }

    # Creates the buckets once the store is ready (S3 CreateBucket, signed
    # with AWS SigV4 by the curl of the RustFS image). Existing buckets are
    # left alone; Norca never creates its backup bucket itself.
    dynamic "task" {
      for_each = length(var.buckets) > 0 ? ["create-buckets"] : []
      labels   = [task.value]

      content {
        driver = "docker"

        lifecycle {
          hook    = "poststart"
          sidecar = false
        }

        config {
          image      = module.placement.image
          entrypoint = ["/bin/sh", "/local/create-buckets.sh"]
        }

        # The root credentials, from the built-in secret store.
        secret "root" {
          path = var.secret_path

          env {
            RUSTFS_ACCESS_KEY = "access_key"
            RUSTFS_SECRET_KEY = "secret_key"
          }
        }

        template {
          destination = "local/create-buckets.sh"
          data        = <<-EOF
            #!/bin/sh
            set -u
            s3="http://127.0.0.1:${var.s3_port}"
            i=0
            until curl -fsS -o /dev/null "$s3/health/ready"; do
              i=$((i + 1))
              if [ "$i" -ge 120 ]; then echo "RustFS is not ready after 10 minutes" >&2; exit 1; fi
              sleep 5
            done
            for bucket in ${join(" ", var.buckets)}; do
              code=$(curl -sS -o /tmp/response -w '%%{http_code}' -X PUT \
                --aws-sigv4 "aws:amz:${var.s3_region}:s3" \
                --user "$RUSTFS_ACCESS_KEY:$RUSTFS_SECRET_KEY" "$s3/$bucket")
              case "$code" in
                200) echo "bucket $bucket created" ;;
                409) echo "bucket $bucket exists" ;;
                *) echo "bucket $bucket: HTTP $code" >&2; cat /tmp/response >&2; exit 1 ;;
              esac
            done
          EOF
        }

        restart {
          attempts = 3
          delay    = "15s"
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
