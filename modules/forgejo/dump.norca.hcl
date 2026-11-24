# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Periodic dump of Forgejo (dump_enabled): forgejo dump of the database
# (SQL), the git repositories and the custom files, without the objects
# already in S3 (packages, LFS, attachments, archives), uploaded to the
# bucket dump_bucket. Norca's own backups cover the cluster state only, not
# the data of the applications.
job "dump" {
  enabled = var.dump_enabled

  id          = "${local.job}-dump"
  name        = "${local.job}-dump"
  region      = rigger.region
  datacenters = module.placement.datacenters
  node_pool   = module.placement.node_pool
  type        = "batch"

  dynamic "constraint" {
    for_each = module.placement.constraints

    content {
      attribute = constraint.value.attribute
      operator  = constraint.value.operator
      value     = constraint.value.value
    }
  }

  periodic {
    cron             = var.dump_cron
    time_zone        = "UTC"
    prohibit_overlap = true
  }

  group "dump" {
    # The host volume of Forgejo, read-only: the dump runs on its node.
    volume "data" {
      type      = "host"
      source    = var.host_volume
      read_only = true
    }

    secret_access {
      path = var.keys_secret_path
    }

    secret_access {
      path = var.storage_secret_path
    }

    task "dump" {
      driver = "docker"
      user   = local.user

      config {
        image      = module.placement.image
        entrypoint = ["/bin/sh", "/local/dump.sh"]
      }

      volume_mount {
        volume      = "data"
        destination = "/var/lib/gitea"
        read_only   = true
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

      # The S3 credentials and endpoint.
      secret "storage" {
        path = var.storage_secret_path

        env {
          AWS_ACCESS_KEY_ID     = "access_key"
          AWS_SECRET_ACCESS_KEY = "secret_key"
        }
      }

      template {
        destination = "secrets/storage.env"
        env         = true
        change_mode = "restart"
        data        = local.storage_env
      }

      template {
        destination = "local/dump.sh"
        data        = <<-EOF
          #!/bin/sh
          set -eu
          mkdir -p /tmp/gitea
          name="forgejo-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
          forgejo -c "$GITEA_APP_INI" dump --type tar.gz --file "/tmp/gitea/$name" \
            --tempdir /tmp/gitea --database sqlite3 --skip-log --skip-index \
            --skip-lfs-data --skip-attachment-data --skip-package-data --skip-repo-archives
          curl -fsS -X PUT -T "/tmp/gitea/$name" \
            --aws-sigv4 "aws:amz:${var.storage_region}:s3" \
            --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
            "${var.storage_use_ssl ? "https" : "http"}://$S3_ENDPOINT/${var.dump_bucket}/${var.dump_prefix}$name"
          echo "uploaded ${var.dump_bucket}/${var.dump_prefix}$name ($(du -h "/tmp/gitea/$name" | cut -f1))"
          rm -f "/tmp/gitea/$name"
        EOF
      }

      restart {
        attempts = 1
        delay    = "1m"
        mode     = "fail"
      }

      resources {
        cpu    = var.dump_resources.cpu
        memory = var.dump_resources.memory
      }
    }
  }
}
