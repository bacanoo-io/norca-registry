# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Periodic Consul snapshot of the datacenter (snapshot_enabled): consul
# snapshot save on a server node (against its local agent), then an upload
# to the S3-compatible store of the Norca backups.
job "snapshot" {
  enabled = var.snapshot_enabled

  id          = local.snapshot
  name        = local.snapshot
  region      = rigger.region
  datacenters = length(var.datacenters) > 0 ? var.datacenters : null
  node_pool   = var.node_pool == "" ? null : var.node_pool
  type        = "batch"

  periodic {
    cron             = var.snapshot_cron
    time_zone        = "UTC"
    prohibit_overlap = true
  }

  group "snapshot" {
    # On a server node: the snapshot is taken through its local agent.
    constraint {
      attribute = runtime("meta.${var.server_node_meta}")
      value     = "true"
    }

    restart {
      attempts = 2
      delay    = "30s"
      mode     = "fail"
    }

    reschedule {
      attempts  = 1
      interval  = "1h"
      unlimited = false
    }

    task "save" {
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      driver = var.driver
      user   = var.driver == "exec" ? "root" : null

      config {
        image        = local.docker ? local.image : null
        network_mode = local.docker ? "host" : null
        entrypoint   = local.docker ? ["/bin/sh"] : null
        command      = local.docker ? null : "/bin/sh"
        args         = ["${runtime_env("NORCA_TASK_DIR")}/save.sh"]
      }

      dynamic "artifact" {
        for_each = local.artifacts

        content {
          source      = artifact.value
          destination = "local"

          dynamic "options" {
            for_each = var.download_checksum != "" ? [var.download_checksum] : []

            content {
              checksum = options.value
            }
          }
        }
      }

      env {
        CONSUL_BIN       = local.consul_bin
        CONSUL_HTTP_ADDR = "http://127.0.0.1:${var.port_http}"
      }

      # The snapshot token, written by the servers' bootstrap task.
      template {
        destination = "secrets/consul_token"
        perms       = "0600"
        data        = "{{ with nomadVar \"nomad/jobs/${local.snapshot}/snapshot\" }}{{ .consul_token.Value | trimSpace }}{{ end }}"
      }

      template {
        destination = "local/save.sh"
        perms       = "0755"
        data        = <<-EOT
          #!/bin/sh
          set -eu
          out="$NORCA_ALLOC_DIR/data/consul.snap"
          "$CONSUL_BIN" snapshot save -token-file="$NORCA_SECRETS_DIR/consul_token" "$out"
          "$CONSUL_BIN" snapshot inspect "$out"
        EOT
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }

    task "upload" {
      driver = "docker"

      config {
        image      = var.snapshot_upload_image
        entrypoint = ["/bin/sh"]
        args       = ["${runtime_env("NORCA_TASK_DIR")}/upload.sh"]
      }

      env {
        AWS_CONFIG_FILE             = "${runtime_env("NORCA_SECRETS_DIR")}/aws/config"
        AWS_SHARED_CREDENTIALS_FILE = var.snapshot_s3_credentials ? "${runtime_env("NORCA_SECRETS_DIR")}/aws/credentials" : null
      }

      template {
        destination = "secrets/aws/config"
        perms       = "0600"
        data        = local.snapshot_aws_config
      }

      # The S3 credentials, from the Variable nomad/jobs/<job>-snapshot.
      dynamic "template" {
        for_each = var.snapshot_s3_credentials ? ["nomad/jobs/${local.snapshot}"] : []

        content {
          destination = "secrets/aws/credentials"
          perms       = "0600"
          data        = <<-EOT
            {{- with nomadVar "${template.value}" }}
            [default]
            aws_access_key_id = {{ .aws_access_key_id.Value | trimSpace }}
            aws_secret_access_key = {{ .aws_secret_access_key.Value | trimSpace }}
            {{- end }}
          EOT
        }
      }

      template {
        destination = "local/upload.sh"
        perms       = "0755"
        data        = local.snapshot_upload
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
