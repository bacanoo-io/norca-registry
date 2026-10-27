# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0
[[- $v := vars . ]]
[[- template "forgejo.validate" . ]]
[[- $job := $v.job_name ]][[ if eq $job "" ]][[ $job = (meta "pack.name" .) ]][[ end ]]
[[- $image := $v.image ]][[ if ne $v.image_digest "" ]][[ $image = printf "%s@%s" $v.image $v.image_digest ]][[ end ]]
[[- $scheme := "http" ]][[ if $v.https_enabled ]][[ $scheme = "https" ]][[ end ]]
[[- $port := int $v.http_port ]]
[[- $rootURL := $v.root_url ]]
[[- if eq $rootURL "" ]]
[[- if or (and $v.https_enabled (eq $port 443)) (and (not $v.https_enabled) (eq $port 80)) ]]
[[- $rootURL = printf "%s://%s/" $scheme $v.domain ]]
[[- else ]]
[[- $rootURL = printf "%s://%s:%d/" $scheme $v.domain $port ]]
[[- end ]]
[[- end ]]

# Forgejo (GPL-3.0-or-later, https://forgejo.org), rendered by the forgejo
# pack: the internal git server and container registry of the cluster. The
# nodes pull the official image; Norca does not ship it. One instance: SQLite
# and the git repositories live on the host volume.
job [[ $job | quote ]] {
[[- template "forgejo.location" . ]]
  type = "service"

  group "forgejo" {
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
      port "http" {
        static = [[ $port ]]
        to     = 3000
[[- if ne $v.host_network "" ]]
        host_network = [[ $v.host_network | quote ]]
[[- end ]]
      }
[[- if $v.ssh_enabled ]]

      port "ssh" {
        static = [[ $v.ssh_port ]]
        to     = 2222
[[- if ne $v.host_network "" ]]
        host_network = [[ $v.host_network | quote ]]
[[- end ]]
      }
[[- end ]]
    }

    volume "data" {
      type      = "host"
      source    = [[ $v.host_volume | quote ]]
      read_only = false
    }

    # The tasks read only the secrets of Forgejo.
    secret_access {
      path = [[ $v.keys_secret_path | quote ]]
    }
[[- if $v.admin_enabled ]]

    secret_access {
      path = [[ $v.admin_secret_path | quote ]]
    }
[[- end ]]
[[- if $v.storage_enabled ]]

    secret_access {
      path = [[ $v.storage_secret_path | quote ]]
    }
[[- end ]]
[[- if $v.https_enabled ]]

    secret_access {
      path = [[ $v.tls_secret_path | quote ]]
    }
[[- end ]]
[[- if and $v.metrics_enabled (ne $v.metrics_token_secret_path "") ]]

    secret_access {
      path = [[ $v.metrics_token_secret_path | quote ]]
    }
[[- end ]]

    service {
      name     = [[ $job | quote ]]
      provider = "nomad"
      port     = "http"
      tags     = [[ if $v.metrics_enabled ]][[ list $scheme "metrics" | toStringList ]][[ else ]][[ list $scheme | toStringList ]][[ end ]]
[[- if $v.https_enabled ]]

      # Norca's HTTP checks verify certificates against the system CAs and
      # connect to the instance address, which the certificate of the domain
      # doesn't name: with HTTPS the checks are TCP checks.
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
      }
[[- else ]]

      check {
        name            = "startup"
        role            = "startup"
        type            = "tcp"
        interval        = "5s"
        timeout         = "2s"
        startup_timeout = [[ $v.startup_timeout | quote ]]
      }

      # /api/healthz checks the database and the cache.
      check {
        name     = "readiness"
        role     = "readiness"
        type     = "http"
        path     = "/api/healthz"
        interval = "10s"
        timeout  = "3s"
      }

      check {
        name     = "liveness"
        role     = "liveness"
        type     = "http"
        path     = "/api/healthz"
        interval = "30s"
        timeout  = "5s"
      }
[[- end ]]
    }
[[- if $v.ssh_enabled ]]

    service {
      name     = "[[ $job ]]-ssh"
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
[[- end ]]

    task "forgejo" {
      driver = "docker"
      user   = "[[ $v.uid ]]:[[ $v.gid ]]"

      config {
        image = [[ $image | quote ]]
        ports = ["http"[[ if $v.ssh_enabled ]], "ssh"[[ end ]]]
      }

      volume_mount {
        volume      = "data"
        destination = "/var/lib/gitea"
      }
[[- template "forgejo.keys" . ]]
[[- if $v.https_enabled ]]

      template {
        data        = "{{ with nomadSecret \"[[ $v.tls_secret_path ]]\" }}{{ .cert }}{{ end }}"
        destination = "secrets/tls.crt"
        uid         = [[ $v.uid ]]
        gid         = [[ $v.gid ]]
        perms       = "0400"
        change_mode = "restart"
      }

      template {
        data        = "{{ with nomadSecret \"[[ $v.tls_secret_path ]]\" }}{{ .key }}{{ end }}"
        destination = "secrets/tls.key"
        uid         = [[ $v.uid ]]
        gid         = [[ $v.gid ]]
        perms       = "0400"
        change_mode = "restart"
      }
[[- end ]]
[[- if $v.storage_enabled ]]
[[- template "forgejo.storage" . ]]
[[- end ]]
[[- if and $v.metrics_enabled (ne $v.metrics_token_secret_path "") ]]

      # The bearer token of /metrics. environment-to-ini writes it into
      # app.ini at every start (Forgejo has no TOKEN_URI for it).
      template {
        data        = "{{ with nomadSecret \"[[ $v.metrics_token_secret_path ]]\" }}{{ .token }}{{ end }}"
        destination = "secrets/metrics_token"
        uid         = [[ $v.uid ]]
        gid         = [[ $v.gid ]]
        perms       = "0400"
        change_mode = "restart"
      }
[[- end ]]

      # app.ini settings (FORGEJO__<section>__<KEY>, applied by the image's
      # environment-to-ini at every start). Secrets are not among them.
      env {
        FORGEJO____APP_NAME                         = [[ $v.app_name | quote ]]
        FORGEJO__server__DOMAIN                     = [[ $v.domain | quote ]]
        FORGEJO__server__ROOT_URL                   = [[ $rootURL | quote ]]
        FORGEJO__server__HTTP_PORT                  = "3000"
[[- if $v.https_enabled ]]
        FORGEJO__server__PROTOCOL                   = "https"
        FORGEJO__server__CERT_FILE                  = "/secrets/tls.crt"
        FORGEJO__server__KEY_FILE                   = "/secrets/tls.key"
[[- end ]]
[[- if $v.ssh_enabled ]]
        FORGEJO__server__DISABLE_SSH                = "false"
        FORGEJO__server__SSH_DOMAIN                 = [[ $v.domain | quote ]]
        FORGEJO__server__SSH_PORT                   = "[[ $v.ssh_port ]]"
        FORGEJO__server__SSH_LISTEN_PORT            = "2222"
[[- else ]]
        FORGEJO__server__DISABLE_SSH                = "true"
        FORGEJO__server__START_SSH_SERVER           = "false"
[[- end ]]
        FORGEJO__server__LFS_START_SERVER           = "true"
        FORGEJO__server__LFS_JWT_SECRET_URI         = "file:/secrets/lfs_jwt_secret"
        FORGEJO__security__INSTALL_LOCK             = "true"
        FORGEJO__security__SECRET_KEY_URI           = "file:/secrets/secret_key"
        FORGEJO__security__INTERNAL_TOKEN_URI       = "file:/secrets/internal_token"
        FORGEJO__oauth2__JWT_SECRET_URI             = "file:/secrets/jwt_secret"
        FORGEJO__database__DB_TYPE                  = "sqlite3"
        FORGEJO__service__DISABLE_REGISTRATION      = "[[ $v.disable_registration ]]"
        FORGEJO__service__REQUIRE_SIGNIN_VIEW       = "[[ $v.require_signin_view ]]"
        FORGEJO__packages__ENABLED                  = "true"
[[- if $v.storage_enabled ]]
        FORGEJO__storage__STORAGE_TYPE              = "minio"
        FORGEJO__storage__MINIO_BUCKET              = [[ $v.storage_bucket | quote ]]
        FORGEJO__storage__MINIO_BUCKET_LOOKUP       = "path"
        FORGEJO__storage__MINIO_LOCATION            = [[ $v.storage_region | quote ]]
        FORGEJO__storage__MINIO_USE_SSL             = "[[ $v.storage_use_ssl ]]"
[[- end ]]
[[- if $v.metrics_enabled ]]
        FORGEJO__metrics__ENABLED                   = "true"
[[- if ne $v.metrics_token_secret_path "" ]]
        FORGEJO__metrics__TOKEN__FILE               = "/secrets/metrics_token"
[[- end ]]
[[- end ]]
        FORGEJO__log__ROOT_PATH                     = "/var/lib/gitea/data/log"
        FORGEJO__log__MODE                          = "console"
[[- range $k, $val := $v.extra_env ]]
        [[ $k ]] = [[ $val | quote ]]
[[- end ]]
      }

      kill_timeout = "30s"

      resources {
        cpu    = [[ $v.resources.cpu ]]
        memory = [[ $v.resources.memory ]]
      }
    }
[[- if $v.admin_enabled ]]

    # Creates the initial admin once Forgejo is ready; an existing user of the
    # name is left alone (the password is only set at creation).
    task "create-admin" {
      driver = "docker"
      user   = "[[ $v.uid ]]:[[ $v.gid ]]"

      lifecycle {
        hook    = "poststart"
        sidecar = false
      }

      config {
        image      = [[ $image | quote ]]
        entrypoint = ["/bin/sh", "/local/create-admin.sh"]
      }

      volume_mount {
        volume      = "data"
        destination = "/var/lib/gitea"
      }
[[- template "forgejo.keys" . ]]
[[- if $v.storage_enabled ]]
[[- template "forgejo.storage" . ]]
[[- end ]]

      secret "admin" {
        path = [[ $v.admin_secret_path | quote ]]

        env {
          FORGEJO_ADMIN_PASSWORD = "password"
        }
      }

      env {
        FORGEJO_ADMIN_USERNAME = [[ $v.admin_username | quote ]]
        FORGEJO_ADMIN_EMAIL    = [[ $v.admin_email | quote ]]
      }

      template {
        destination = "local/create-admin.sh"
        data        = <<-EOF
          #!/bin/sh
          set -eu
          mkdir -p /tmp/gitea
          i=0
          until curl -fsSk -o /dev/null "[[ $scheme ]]://127.0.0.1:3000/api/healthz"; do
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
[[- end ]]
  }
}
