# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# PostgreSQL (PostgreSQL License, https://www.postgresql.org): one server
# with its data on a host volume. The nodes pull the official image; Norca
# does not ship it. No replication or failover: a lost node means a restore
# from the dumps.
job "postgres" {
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

  group "postgres" {
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
      port "db" {
        static       = var.port
        to           = 5432
        host_network = var.host_network == "" ? null : var.host_network
      }
    }

    volume "data" {
      type      = "host"
      source    = var.host_volume
      read_only = false
    }

    # The tasks read only the secrets of the server and of its roles.
    dynamic "secret_access" {
      for_each = local.secret_paths

      content {
        path = secret_access.value
      }
    }

    service {
      name     = local.job
      provider = "nomad"
      port     = "db"
      tags     = local.tls ? ["postgres", "tls"] : ["postgres"]

      # The workload certificate of the server (valid for
      # <job>.service.<namespace>.norca) and the trust bundle of the region:
      # the server terminates TLS itself (app mode, no sidecar).
      dynamic "mtls" {
        for_each = var.tls_mode == "mtls" ? [1] : []

        content {
          mode = "app"
        }
      }

      # Native checks are HTTP or TCP: the server accepts connections.
      check {
        name            = "startup"
        role            = "startup"
        type            = "tcp"
        interval        = "5s"
        timeout         = "2s"
        startup_timeout = var.startup_timeout
      }

      check {
        name     = "readiness"
        role     = "readiness"
        type     = "tcp"
        interval = "10s"
        timeout  = "3s"
      }

      check {
        name     = "liveness"
        role     = "liveness"
        type     = "tcp"
        interval = "15s"
        timeout  = "3s"

        check_restart {
          limit = 3
          grace = "60s"
        }
      }
    }

    task "postgres" {
      driver = "docker"
      user   = local.user

      config {
        image      = module.placement.image
        ports      = ["db"]
        entrypoint = local.tls ? ["/bin/sh", "/local/start.sh"] : null
        args       = local.args
      }

      volume_mount {
        volume      = "data"
        destination = "/var/lib/postgresql"
      }

      # The password of the superuser, read by the image at the first start
      # (initdb) only. A changed secret does not change the password of an
      # existing database: ALTER ROLE it, then put the new version.
      template {
        data        = "{{ with nomadSecret \"${var.superuser_secret_path}\" }}{{ .password }}{{ end }}"
        destination = "secrets/superuser_password"
        uid         = var.uid
        gid         = var.gid
        perms       = "0400"
        change_mode = "noop"
      }

      dynamic "template" {
        for_each = var.tls_mode == "secret" ? ["cert", "key"] : []

        content {
          data        = "{{ with nomadSecret \"${var.tls_secret_path}\" }}{{ .${template.value} }}{{ end }}"
          destination = "secrets/tls/${template.value}.pem"
          uid         = var.uid
          gid         = var.gid
          perms       = "0400"
          change_mode = "noop"
        }
      }

      # PostgreSQL needs a key file only its user can read: the start script
      # copies the certificate and key to /tmp/tls (0600), and copies them
      # again and reloads the server (SIGHUP) when they change (renewals of
      # the workload certificate, or a new version of the secret). The loop
      # never exits: the server would treat a child that exits abnormally as
      # a crash.
      dynamic "template" {
        for_each = local.tls ? [local.tls_src] : []

        content {
          destination = "local/start.sh"
          data        = <<-EOF
            #!/bin/sh
            set -eu
            src=${template.value}
            dst=/tmp/tls
            copy() {
              cp "$src/cert.pem" "$dst/server.crt.new" && cp "$src/key.pem" "$dst/server.key.new" &&
                chmod 0600 "$dst/server.key.new" &&
                mv "$dst/server.crt.new" "$dst/server.crt" && mv "$dst/server.key.new" "$dst/server.key"
            }
            mkdir -p "$dst"
            chmod 0700 "$dst"
            copy
            (
              while :; do
                sleep 60
                if ! cmp -s "$src/cert.pem" "$dst/server.crt" || ! cmp -s "$src/key.pem" "$dst/server.key"; then
                  copy && kill -HUP 1 && echo "TLS certificate reloaded" || :
                fi
              done
            ) &
            exec docker-entrypoint.sh "$@"
          EOF
        }
      }

      # Only TLS connections over TCP (the image's own rules allow both).
      dynamic "template" {
        for_each = var.tls_required ? [1] : []

        content {
          destination = "local/pg_hba.conf"
          data        = <<-EOF
            # TYPE   DATABASE USER ADDRESS METHOD
            local    all      all          trust
            hostssl  all      all  all     scram-sha-256
          EOF
        }
      }

      env {
        POSTGRES_USER          = var.superuser
        POSTGRES_PASSWORD_FILE = "/secrets/superuser_password"
        POSTGRES_INITDB_ARGS   = "--auth-host=scram-sha-256 --auth-local=trust"
      }

      # Fast shutdown: active sessions are disconnected, then a checkpoint.
      kill_signal  = "SIGINT"
      kill_timeout = "60s"

      resources {
        cpu    = var.resources.cpu
        memory = var.resources.memory
      }
    }

    # Creates the roles and databases once the server accepts connections:
    # missing roles and databases are created, the passwords set again from
    # the secrets at every run, existing databases are kept. It runs after
    # every start of the server and exits.
    dynamic "task" {
      for_each = local.setup ? ["setup"] : []
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
          entrypoint = ["/bin/sh", "/local/setup.sh"]
        }

        secret "superuser" {
          path = var.superuser_secret_path

          env {
            PGPASSWORD = "password"
          }
        }

        dynamic "secret" {
          for_each = var.databases
          labels   = ["db-${secret.key}"]

          content {
            path = secret.value.secret_path
            env  = { "DB_${secret.key}_PASSWORD" = "password" }
          }
        }

        # Optional: without the secret the monitoring role is skipped.
        dynamic "secret" {
          for_each = var.monitoring_enabled ? [var.monitoring_secret_path] : []
          labels   = ["monitoring"]

          content {
            path     = secret.value
            optional = true
            timeout  = "15s"

            env {
              MONITORING_PASSWORD = "password"
            }
          }
        }

        env {
          PGHOST     = runtime_env("NORCA_IP_db")
          PGPORT     = runtime_env("NORCA_HOST_PORT_db")
          PGUSER     = var.superuser
          PGDATABASE = "postgres"
          PGSSLMODE  = var.tls_required ? "require" : null
        }

        template {
          destination = "local/role.sql"
          data        = <<-EOF
            -- Creates the login role :role if it does not exist and sets its
            -- password from the environment variable PW.
            \getenv pw PW
            SELECT format('CREATE ROLE %I LOGIN', :'role')
              WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'role') \gexec
            ALTER ROLE :"role" WITH LOGIN PASSWORD :'pw';
          EOF
        }

        template {
          destination = "local/database.sql"
          data        = <<-EOF
            -- Creates the database :db owned by :role if it does not exist.
            SELECT format('CREATE DATABASE %I OWNER %I', :'db', :'role')
              WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'db') \gexec
          EOF
        }

        template {
          destination = "local/setup.sh"
          data        = local.setup_script
        }

        restart {
          attempts = 3
          delay    = "15s"
          mode     = "fail"
        }

        resources {
          cpu    = 50
          memory = 64
        }
      }
    }
  }
}
