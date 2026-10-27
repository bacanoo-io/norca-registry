# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0
[[- $v := vars . ]]
[[- template "postgres.validate" . ]]
[[- $job := $v.job_name ]][[ if eq $job "" ]][[ $job = (meta "pack.name" .) ]][[ end ]]
[[- $image := $v.image ]][[ if ne $v.image_digest "" ]][[ $image = printf "%s@%s" $v.image $v.image_digest ]][[ end ]]
[[- $tls := ne $v.tls_mode "none" ]]
[[- $setup := or $v.databases $v.monitoring_enabled ]]
[[- $args := list "postgres" ]]
[[- if $tls ]][[ $args = concat $args (list "-c" "ssl=on" "-c" "ssl_cert_file=/tmp/tls/server.crt" "-c" "ssl_key_file=/tmp/tls/server.key") ]][[ end ]]
[[- if $v.tls_required ]][[ $args = concat $args (list "-c" "hba_file=/local/pg_hba.conf") ]][[ end ]]
[[- range $k, $val := $v.settings ]][[ $args = concat $args (list "-c" (printf "%s=%s" $k $val)) ]][[ end ]]

# PostgreSQL (PostgreSQL License, https://www.postgresql.org), rendered by the
# postgres pack: one server with its data on a host volume. The nodes pull the
# official image; Norca does not ship it. No replication or failover: a lost
# node means a restore from the dumps.
job [[ $job | quote ]] {
[[- template "postgres.location" . ]]
  type = "service"

  group "postgres" {
    count = 1

    # A single instance with its data on one node: evictions are refused, and
    # a node drain moves it only when its deadline is reached.
    disruption {
      min_healthy = "1"
    }

    update {
      max_parallel      = 1
      health_check      = "checks"
      min_healthy_time  = "10s"
      healthy_deadline  = [[ $v.healthy_deadline | quote ]]
      progress_deadline = "0"
      auto_revert       = false
    }

    network {
      port "db" {
        static = [[ $v.port ]]
        to     = 5432
[[- if ne $v.host_network "" ]]
        host_network = [[ $v.host_network | quote ]]
[[- end ]]
      }
    }

    volume "data" {
      type      = "host"
      source    = [[ $v.host_volume | quote ]]
      read_only = false
    }

    # The tasks read only the secrets of the server and of its roles.
    secret_access {
      path = [[ $v.superuser_secret_path | quote ]]
    }
[[- range $d := $v.databases ]]

    secret_access {
      path = [[ $d.secret_path | quote ]]
    }
[[- end ]]
[[- if $v.monitoring_enabled ]]

    secret_access {
      path = [[ $v.monitoring_secret_path | quote ]]
    }
[[- end ]]
[[- if eq $v.tls_mode "secret" ]]

    secret_access {
      path = [[ $v.tls_secret_path | quote ]]
    }
[[- end ]]

    service {
      name     = [[ $job | quote ]]
      provider = "nomad"
      port     = "db"
      tags     = ["postgres"[[ if $tls ]], "tls"[[ end ]]]
[[- if eq $v.tls_mode "mtls" ]]

      # The workload certificate of the server (valid for
      # [[ $job ]].service.<namespace>.nomad) and the trust bundle of the region:
      # the server terminates TLS itself (app mode, no sidecar).
      mtls {
        mode = "app"
      }
[[- end ]]

      # Native checks are HTTP or TCP: the server accepts connections.
      check {
        name            = "startup"
        role            = "startup"
        type            = "tcp"
        interval        = "5s"
        timeout         = "2s"
        startup_timeout = [[ $v.startup_timeout | quote ]]
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
      user   = "[[ $v.uid ]]:[[ $v.gid ]]"

      config {
        image = [[ $image | quote ]]
        ports = ["db"]
[[- if $tls ]]
        entrypoint = ["/bin/sh", "/local/start.sh"]
[[- end ]]
        args  = [[ $args | toStringList ]]
      }

      volume_mount {
        volume      = "data"
        destination = "/var/lib/postgresql"
      }

      # The password of the superuser, read by the image at the first start
      # (initdb) only. A changed secret does not change the password of an
      # existing database: ALTER ROLE it, then put the new version.
      template {
        data        = "{{ with nomadSecret \"[[ $v.superuser_secret_path ]]\" }}{{ .password }}{{ end }}"
        destination = "secrets/superuser_password"
        uid         = [[ $v.uid ]]
        gid         = [[ $v.gid ]]
        perms       = "0400"
        change_mode = "noop"
      }
[[- if eq $v.tls_mode "secret" ]]
[[- range $item := list "cert" "key" ]]

      template {
        data        = "{{ with nomadSecret \"[[ $v.tls_secret_path ]]\" }}{{ .[[ $item ]] }}{{ end }}"
        destination = "secrets/tls/[[ $item ]].pem"
        uid         = [[ $v.uid ]]
        gid         = [[ $v.gid ]]
        perms       = "0400"
        change_mode = "noop"
      }
[[- end ]]
[[- end ]]
[[- if $tls ]]
[[- $src := "/secrets/mtls" ]][[ if eq $v.tls_mode "secret" ]][[ $src = "/secrets/tls" ]][[ end ]]

      # PostgreSQL needs a key file only its user can read: the start script
      # copies the certificate and key to /tmp/tls (0600), and copies them
      # again and reloads the server (SIGHUP) when they change ([[ if eq $v.tls_mode "mtls" ]]renewals of
      # the workload certificate[[ else ]]a new version of the secret[[ end ]]). The loop never exits: the
      # server would treat a child that exits abnormally as a crash.
      template {
        destination = "local/start.sh"
        data        = <<-EOF
          #!/bin/sh
          set -eu
          src=[[ $src ]]
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
[[- end ]]
[[- if $v.tls_required ]]

      # Only TLS connections over TCP (the image's own rules allow both).
      template {
        destination = "local/pg_hba.conf"
        data        = <<-EOF
          # TYPE   DATABASE USER ADDRESS METHOD
          local    all      all          trust
          hostssl  all      all  all     scram-sha-256
        EOF
      }
[[- end ]]

      env {
        POSTGRES_USER          = [[ $v.superuser | quote ]]
        POSTGRES_PASSWORD_FILE = "/secrets/superuser_password"
        POSTGRES_INITDB_ARGS   = "--auth-host=scram-sha-256 --auth-local=trust"
      }

      # Fast shutdown: active sessions are disconnected, then a checkpoint.
      kill_signal  = "SIGINT"
      kill_timeout = "60s"

      resources {
        cpu    = [[ $v.resources.cpu ]]
        memory = [[ $v.resources.memory ]]
      }
    }
[[- if $setup ]]

    # Creates the roles and databases once the server accepts connections:
    # missing roles and databases are created, the passwords set again from
    # the secrets at every run, existing databases are kept. It runs after
    # every start of the server and exits.
    task "setup" {
      driver = "docker"
      user   = "[[ $v.uid ]]:[[ $v.gid ]]"

      lifecycle {
        hook    = "poststart"
        sidecar = false
      }

      config {
        image      = [[ $image | quote ]]
        entrypoint = ["/bin/sh", "/local/setup.sh"]
      }
[[- template "postgres.superuser_env" . ]]
[[- range $i, $d := $v.databases ]]

      secret "db-[[ $i ]]" {
        path = [[ $d.secret_path | quote ]]

        env {
          DB_[[ $i ]]_PASSWORD = "password"
        }
      }
[[- end ]]
[[- if $v.monitoring_enabled ]]

      # Optional: without the secret the monitoring role is skipped.
      secret "monitoring" {
        path     = [[ $v.monitoring_secret_path | quote ]]
        optional = true
        timeout  = "15s"

        env {
          MONITORING_PASSWORD = "password"
        }
      }
[[- end ]]

      env {
        PGHOST    = "${NOMAD_IP_db}"
        PGPORT    = "${NOMAD_HOST_PORT_db}"
        PGUSER    = [[ $v.superuser | quote ]]
        PGDATABASE = "postgres"
[[- if $v.tls_required ]]
        PGSSLMODE = "require"
[[- end ]]
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
        data        = <<-EOF
          #!/bin/sh
          set -eu
          i=0
          until pg_isready -q; do
            i=$((i + 1))
            if [ "$i" -ge 120 ]; then echo "PostgreSQL is not ready after 10 minutes" >&2; exit 1; fi
            sleep 5
          done
          run() { psql -X -q -v ON_ERROR_STOP=1 "$@"; }
[[- range $i, $d := $v.databases ]]
          PW="$DB_[[ $i ]]_PASSWORD" run -v role=[[ $d.user | squote ]] -f /local/role.sql
          run -v role=[[ $d.user | squote ]] -v db=[[ $d.name | squote ]] -f /local/database.sql
          echo "role [[ $d.user ]] and database [[ $d.name ]] ready"
[[- end ]]
[[- if $v.monitoring_enabled ]]
          if [ -n "$${MONITORING_PASSWORD:-}" ]; then
            PW="$MONITORING_PASSWORD" run -v role=[[ $v.monitoring_user | squote ]] -f /local/role.sql
            run -c 'GRANT pg_monitor TO [[ $v.monitoring_user ]]'
            echo "monitoring role [[ $v.monitoring_user ]] ready (pg_monitor)"
          else
            echo "secret [[ $v.monitoring_secret_path ]] not found: monitoring role [[ $v.monitoring_user ]] skipped"
          fi
[[- end ]]
        EOF
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
[[- end ]]
  }
}
