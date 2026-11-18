# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Forgejo (GPL-3.0-or-later, https://forgejo.org): the internal git server
# and container registry of the cluster. The nodes pull the official image;
# Norca does not ship it. One instance: SQLite and the git repositories
# live on the host volume.
job "forgejo" {
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

  group "forgejo" {
    count = 1

    # A single instance with its data on one node: evictions are refused,
    # and a node drain moves it only when its deadline is reached.
    disruption {
      min_healthy = "1"
    }

    update {
      max_parallel      = 1
      health_check      = "checks"
      min_healthy_time  = "10s"
      healthy_deadline  = var.healthy_deadline
      progress_deadline = "0"
      auto_revert       = false
    }

    network {
      port "http" {
        static       = var.http_port
        to           = 3000
        host_network = var.host_network == "" ? null : var.host_network
      }

      dynamic "port" {
        for_each = var.ssh_enabled ? ["ssh"] : []
        labels   = [port.value]

        content {
          static       = var.ssh_port
          to           = 2222
          host_network = var.host_network == "" ? null : var.host_network
        }
      }
    }

    volume "data" {
      type      = "host"
      source    = var.host_volume
      read_only = false
    }

    # The tasks read only the secrets of Forgejo.
    dynamic "secret_access" {
      for_each = local.secret_paths

      content {
        path = secret_access.value
      }
    }

    service {
      name     = local.job
      provider = "nomad"
      port     = "http"
      tags     = var.metrics_enabled ? [local.scheme, "metrics"] : [local.scheme]

      check {
        name            = "startup"
        role            = "startup"
        type            = "tcp"
        interval        = "5s"
        timeout         = "2s"
        startup_timeout = var.startup_timeout
      }

      # Norca's HTTP checks verify certificates against the system CAs and
      # connect to the instance address, which the certificate of the
      # domain doesn't name: with HTTPS the checks are TCP checks. Without
      # it, /api/healthz checks the database and the cache.
      check {
        name     = "readiness"
        role     = "readiness"
        type     = var.https_enabled ? "tcp" : "http"
        path     = var.https_enabled ? null : "/api/healthz"
        interval = "10s"
        timeout  = "3s"
      }

      check {
        name     = "liveness"
        role     = "liveness"
        type     = var.https_enabled ? "tcp" : "http"
        path     = var.https_enabled ? null : "/api/healthz"
        interval = var.https_enabled ? "15s" : "30s"
        timeout  = var.https_enabled ? "3s" : "5s"
      }
    }

    dynamic "service" {
      for_each = var.ssh_enabled ? ["${local.job}-ssh"] : []

      content {
        name     = service.value
        provider = "nomad"
        port     = "ssh"

        check {
          name     = "readiness"
          role     = "readiness"
          type     = "tcp"
          interval = "15s"
          timeout  = "3s"
        }
      }
    }

    task "forgejo" {
      driver = "docker"
      user   = local.user

      config {
        image = module.placement.image
        ports = var.ssh_enabled ? ["http", "ssh"] : ["http"]
      }

      volume_mount {
        volume      = "data"
        destination = "/var/lib/gitea"
      }

      # The keys, the certificate of HTTPS and the bearer token of /metrics
      # as files below secrets/, owned by the container user. environment-
      # to-ini writes the token into app.ini at every start (Forgejo has no
      # TOKEN_URI for it).
      dynamic "template" {
        for_each = concat(local.key_files, local.tls_files)

        content {
          data        = "{{ with nomadSecret \"${template.value.path}\" }}{{ .${template.value.item} }}{{ end }}"
          destination = template.value.file
          uid         = var.uid
          gid         = var.gid
          perms       = "0400"
          change_mode = "restart"
        }
      }

      # The S3 credentials, from the built-in secret store. Forgejo's S3
      # client reads them from the environment when app.ini has no keys.
      dynamic "secret" {
        for_each = var.storage_enabled ? [var.storage_secret_path] : []
        labels   = ["storage"]

        content {
          path = secret.value

          env {
            AWS_ACCESS_KEY_ID     = "access_key"
            AWS_SECRET_ACCESS_KEY = "secret_key"
          }
        }
      }

      dynamic "template" {
        for_each = var.storage_enabled ? [local.storage_env] : []

        content {
          destination = "secrets/storage.env"
          env         = true
          change_mode = "restart"
          data        = template.value
        }
      }

      dynamic "template" {
        for_each = local.metrics_files

        content {
          data        = "{{ with nomadSecret \"${template.value.path}\" }}{{ .${template.value.item} }}{{ end }}"
          destination = template.value.file
          uid         = var.uid
          gid         = var.gid
          perms       = "0400"
          change_mode = "restart"
        }
      }

      env = local.env

      kill_timeout = "30s"

      resources {
        cpu    = var.resources.cpu
        memory = var.resources.memory
      }
    }

    # Creates the initial admin once Forgejo is ready; an existing user of
    # the name is left alone (the password is only set at creation).
    dynamic "task" {
      for_each = var.admin_enabled ? ["create-admin"] : []
      labels   = [task.value]

      content {
        driver = "docker"
        user   = local.user

        lifecycle {
          hook    = "poststart"
          sidecar = false
        }

        config {
          image      = module.placement.image
          entrypoint = ["/bin/sh", "/local/create-admin.sh"]
        }

        volume_mount {
          volume      = "data"
          destination = "/var/lib/gitea"
        }

        dynamic "template" {
          for_each = local.key_files

          content {
            data        = "{{ with nomadSecret \"${template.value.path}\" }}{{ .${template.value.item} }}{{ end }}"
            destination = template.value.file
            uid         = var.uid
            gid         = var.gid
            perms       = "0400"
            change_mode = "restart"
          }
        }

        dynamic "secret" {
          for_each = var.storage_enabled ? [var.storage_secret_path] : []
          labels   = ["storage"]

          content {
            path = secret.value

            env {
              AWS_ACCESS_KEY_ID     = "access_key"
              AWS_SECRET_ACCESS_KEY = "secret_key"
            }
          }
        }

        dynamic "template" {
          for_each = var.storage_enabled ? [local.storage_env] : []

          content {
            destination = "secrets/storage.env"
            env         = true
            change_mode = "restart"
            data        = template.value
          }
        }

        secret "admin" {
          path = var.admin_secret_path

          env {
            FORGEJO_ADMIN_PASSWORD = "password"
          }
        }

        env {
          FORGEJO_ADMIN_USERNAME = var.admin_username
          FORGEJO_ADMIN_EMAIL    = var.admin_email
        }

        template {
          destination = "local/create-admin.sh"
          data        = <<-EOF
            #!/bin/sh
            set -eu
            mkdir -p /tmp/gitea
            i=0
            until curl -fsSk -o /dev/null "${local.scheme}://127.0.0.1:3000/api/healthz"; do
              i=$((i + 1))
              if [ "$i" -ge 120 ]; then echo "Forgejo is not ready after 10 minutes" >&2; exit 1; fi
              sleep 5
            done
            if forgejo -c "$GITEA_APP_INI" admin user list | awk 'NR > 1 { print $2 }' | grep -qx "$FORGEJO_ADMIN_USERNAME"; then
              echo "user $FORGEJO_ADMIN_USERNAME exists"
              exit 0
            fi
            forgejo -c "$GITEA_APP_INI" admin user create --admin \
              --username "$FORGEJO_ADMIN_USERNAME" --email "$FORGEJO_ADMIN_EMAIL" \
              --password "$FORGEJO_ADMIN_PASSWORD" --must-change-password=false
            echo "admin $FORGEJO_ADMIN_USERNAME created"
          EOF
        }

        restart {
          attempts = 3
          delay    = "15s"
          mode     = "fail"
        }

        resources {
          cpu    = 100
          memory = 256
        }
      }
    }
  }
}
