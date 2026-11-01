# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The PostgreSQL operator of the dynamic secrets. Build it with
#
#   CGO_ENABLED=0 go build -o postgres-operator .
#
# from a checkout next to the Norca repository, publish the binary, set its
# address in the artifact block,
# and write the admin credential before the job runs:
#
#   norca secret put -namespace apps operators/postgres/admin password=...
#
# It serves the leader with its workload certificate (mtls mode app). The default
# change_mode of the secret restarts the task when the password is rotated.
job "postgres-operator" {
  namespace = "apps"

  group "operator" {
    count = 2

    network {
      port "api" {}
    }

    secret_access {
      path = "operators/postgres/*"
    }

    service {
      name = "postgres-operator"
      port = "api"

      mtls {
        mode = "app"
      }
    }

    task "operator" {
      driver = "exec"

      config {
        command = "local/postgres-operator"
      }

      artifact {
        source = "https://example.com/postgres-operator"
      }

      env {
        PGHOST     = "db.internal"
        PGDATABASE = "orders"
        PGUSER     = "norca_operator"
        PGSSLMODE  = "require"
      }

      secret "admin" {
        path = "operators/postgres/admin"

        env {
          PGPASSWORD = "password"
        }
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
