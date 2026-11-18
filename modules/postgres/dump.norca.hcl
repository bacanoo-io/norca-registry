# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Periodic dump of PostgreSQL (dump_enabled): pg_dumpall of every database
# and the roles (gzip), uploaded to the bucket dump_bucket. Norca's own
# backups cover the cluster state only, not the data of the applications.
job "dump" {
  enabled = var.dump_enabled

  id          = "${local.job}-dump"
  name        = "${local.job}-dump"
  region      = rig.region
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
    secret_access {
      path = var.superuser_secret_path
    }

    secret_access {
      path = var.dump_storage_secret_path
    }

    # The dump goes into the shared allocation directory; the upload task
    # sends it once the dump task has finished.
    task "dump" {
      driver = "docker"
      user   = local.user

      config {
        image      = module.placement.image
        entrypoint = ["/bin/sh", "/local/dump.sh"]
      }

      secret "superuser" {
        path = var.superuser_secret_path

        env {
          PGPASSWORD = "password"
        }
      }

      # The server: the first instance of its service in the native catalog.
      template {
        destination = "secrets/server.env"
        env         = true
        data        = <<-EOF
          {{- range $i, $s := nomadService "${local.job}" }}{{ if eq $i 0 }}
          PGHOST={{ $s.Address }}
          PGPORT={{ $s.Port }}
          {{- end }}{{ end }}
        EOF
      }

      env {
        PGUSER    = var.superuser
        PGSSLMODE = var.tls_required ? "require" : null
      }

      template {
        destination = "local/dump.sh"
        data        = <<-EOF
          #!/bin/sh
          set -eu
          umask 077
          name="${local.job}-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"
          pg_dumpall --clean --if-exists | gzip > "$NORCA_ALLOC_DIR/data/$name.tmp"
          mv "$NORCA_ALLOC_DIR/data/$name.tmp" "$NORCA_ALLOC_DIR/data/$name"
          echo "$name" > "$NORCA_ALLOC_DIR/data/dump.name"
          echo "dumped $name ($(du -h "$NORCA_ALLOC_DIR/data/$name" | cut -f1))"
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

    # Uploads the dump with an S3 PUT signed with AWS SigV4 by curl.
    task "upload" {
      driver = "docker"
      # The user of the dump task, which owns the file (umask 077).
      user = local.user

      lifecycle {
        hook = "poststop"
      }

      config {
        image      = var.dump_upload_image
        entrypoint = ["/bin/sh", "/local/upload.sh"]
      }

      secret "storage" {
        path = var.dump_storage_secret_path

        env {
          AWS_ACCESS_KEY_ID     = "access_key"
          AWS_SECRET_ACCESS_KEY = "secret_key"
        }
      }

      template {
        destination = "secrets/storage.env"
        env         = true
        data        = local.dump_storage_env
      }

      template {
        destination = "local/upload.sh"
        data        = <<-EOF
          #!/bin/sh
          set -eu
          dir="$NORCA_ALLOC_DIR/data"
          if [ ! -s "$dir/dump.name" ]; then echo "no dump to upload (the dump task failed)" >&2; exit 1; fi
          name=$(cat "$dir/dump.name")
          curl -fsS -X PUT -T "$dir/$name" \
            --aws-sigv4 "aws:amz:${var.dump_storage_region}:s3" \
            --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
            "${var.dump_storage_use_ssl ? "https" : "http"}://$S3_ENDPOINT/${var.dump_bucket}/${var.dump_prefix}$name"
          echo "uploaded ${var.dump_bucket}/${var.dump_prefix}$name"
          rm -f "$dir/$name" "$dir/dump.name"
        EOF
      }

      restart {
        attempts = 1
        delay    = "1m"
        mode     = "fail"
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
