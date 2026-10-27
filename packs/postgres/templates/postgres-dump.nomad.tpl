[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0

Renders nothing (no job) unless dump_enabled.
*/ -]]
[[- $v := vars . ]]
[[- if $v.dump_enabled ]]
[[- $job := $v.job_name ]][[ if eq $job "" ]][[ $job = (meta "pack.name" .) ]][[ end ]]
[[- $image := $v.image ]][[ if ne $v.image_digest "" ]][[ $image = printf "%s@%s" $v.image $v.image_digest ]][[ end ]]
[[- $s3scheme := "http" ]][[ if $v.dump_storage_use_ssl ]][[ $s3scheme = "https" ]][[ end -]]

# Periodic dump of PostgreSQL, rendered by the postgres pack: pg_dumpall of
# every database and the roles (gzip), uploaded to the bucket [[ $v.dump_bucket ]].
# Norca's own backups cover the cluster state only, not the data of the
# applications.
job "[[ $job ]]-dump" {
  [[- template "postgres.location" . ]]
  type = "batch"

  periodic {
    cron             = [[ $v.dump_cron | quote ]]
    time_zone        = "UTC"
    prohibit_overlap = true
  }

  group "dump" {
    secret_access {
      path = [[ $v.superuser_secret_path | quote ]]
    }

    secret_access {
      path = [[ $v.dump_storage_secret_path | quote ]]
    }

    # The dump goes into the shared allocation directory; the upload task
    # sends it once the dump task has finished.
    task "dump" {
      driver = "docker"
      user   = "[[ $v.uid ]]:[[ $v.gid ]]"

      config {
        image      = [[ $image | quote ]]
        entrypoint = ["/bin/sh", "/local/dump.sh"]
      }
      [[- template "postgres.superuser_env" . ]]

      # The server: the first instance of the service [[ $job ]] in the native catalog.
      template {
        destination = "secrets/server.env"
        env         = true
        data        = <<-EOF
          {{- range $i, $s := nomadService "[[ $job ]]" }}{{ if eq $i 0 }}
          PGHOST={{ $s.Address }}
          PGPORT={{ $s.Port }}
          {{- end }}{{ end }}
        EOF
      }

      env {
        PGUSER = [[ $v.superuser | quote ]]
        [[- if $v.tls_required ]]
        PGSSLMODE = "require"
        [[- end ]]
      }

      template {
        destination = "local/dump.sh"
        data        = <<-EOF
          #!/bin/sh
          set -eu
          umask 077
          name="[[ $job ]]-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"
          pg_dumpall --clean --if-exists | gzip > "$NOMAD_ALLOC_DIR/data/$name.tmp"
          mv "$NOMAD_ALLOC_DIR/data/$name.tmp" "$NOMAD_ALLOC_DIR/data/$name"
          echo "$name" > "$NOMAD_ALLOC_DIR/data/dump.name"
          echo "dumped $name ($(du -h "$NOMAD_ALLOC_DIR/data/$name" | cut -f1))"
        EOF
      }

      restart {
        attempts = 1
        delay    = "1m"
        mode     = "fail"
      }

      resources {
        cpu    = [[ $v.dump_resources.cpu ]]
        memory = [[ $v.dump_resources.memory ]]
      }
    }

    # Uploads the dump with an S3 PUT signed with AWS SigV4 by curl.
    task "upload" {
      driver = "docker"
      # The user of the dump task, which owns the file (umask 077).
      user = "[[ $v.uid ]]:[[ $v.gid ]]"

      lifecycle {
        hook = "poststop"
      }

      config {
        image      = [[ $v.dump_upload_image | quote ]]
        entrypoint = ["/bin/sh", "/local/upload.sh"]
      }

      secret "storage" {
        path = [[ $v.dump_storage_secret_path | quote ]]

        env {
          AWS_ACCESS_KEY_ID     = "access_key"
          AWS_SECRET_ACCESS_KEY = "secret_key"
        }
      }

      # The S3 endpoint: [[ if ne $v.dump_storage_endpoint "" ]]dump_storage_endpoint[[ else ]]the first instance of the service [[ $v.dump_storage_service ]] in the native catalog[[ end ]].
      template {
        destination = "secrets/storage.env"
        env         = true
        data        = <<-EOF
[[- if ne $v.dump_storage_endpoint "" ]]
          S3_ENDPOINT=[[ $v.dump_storage_endpoint ]]
[[- else ]]
          {{- range $i, $s := nomadService "[[ $v.dump_storage_service ]]" }}{{ if eq $i 0 }}
          S3_ENDPOINT={{ $s.Address }}:{{ $s.Port }}
          {{- end }}{{ end }}
[[- end ]]
        EOF
      }

      template {
        destination = "local/upload.sh"
        data        = <<-EOF
          #!/bin/sh
          set -eu
          dir="$NOMAD_ALLOC_DIR/data"
          if [ ! -s "$dir/dump.name" ]; then echo "no dump to upload (the dump task failed)" >&2; exit 1; fi
          name=$(cat "$dir/dump.name")
          curl -fsS -X PUT -T "$dir/$name" \
            --aws-sigv4 "aws:amz:[[ $v.dump_storage_region ]]:s3" \
            --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
            "[[ $s3scheme ]]://$S3_ENDPOINT/[[ $v.dump_bucket ]]/[[ $v.dump_prefix ]]$name"
          echo "uploaded [[ $v.dump_bucket ]]/[[ $v.dump_prefix ]]$name"
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
[[- end ]]
