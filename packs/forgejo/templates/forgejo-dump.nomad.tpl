[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0

Renders nothing (no job) unless dump_enabled.
*/ -]]
[[- $v := vars . ]]
[[- if $v.dump_enabled ]]
[[- $job := $v.job_name ]][[ if eq $job "" ]][[ $job = (meta "pack.name" .) ]][[ end ]]
[[- $image := $v.image ]][[ if ne $v.image_digest "" ]][[ $image = printf "%s@%s" $v.image $v.image_digest ]][[ end ]]
[[- $s3scheme := "http" ]][[ if $v.storage_use_ssl ]][[ $s3scheme = "https" ]][[ end -]]

# Periodic dump of Forgejo, rendered by the forgejo pack: forgejo dump of the
# database (SQL), the git repositories and the custom files, without the
# objects already in S3 (packages, LFS, attachments, archives), uploaded to
# the bucket [[ $v.dump_bucket ]]. Norca's own backups cover the cluster state only,
# not the data of the applications.
job "[[ $job ]]-dump" {
  [[- template "forgejo.location" . ]]
  type = "batch"

  periodic {
    cron             = [[ $v.dump_cron | quote ]]
    time_zone        = "UTC"
    prohibit_overlap = true
  }

  group "dump" {
    # The host volume of Forgejo, read-only: the dump runs on its node.
    volume "data" {
      type      = "host"
      source    = [[ $v.host_volume | quote ]]
      read_only = true
    }

    secret_access {
      path = [[ $v.keys_secret_path | quote ]]
    }

    secret_access {
      path = [[ $v.storage_secret_path | quote ]]
    }

    task "dump" {
      driver = "docker"
      user   = "[[ $v.uid ]]:[[ $v.gid ]]"

      config {
        image      = [[ $image | quote ]]
        entrypoint = ["/bin/sh", "/local/dump.sh"]
      }

      volume_mount {
        volume      = "data"
        destination = "/var/lib/gitea"
        read_only   = true
      }
      [[- template "forgejo.keys" . ]]
      [[- template "forgejo.storage" . ]]

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
            --aws-sigv4 "aws:amz:[[ $v.storage_region ]]:s3" \
            --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
            "[[ $s3scheme ]]://$S3_ENDPOINT/[[ $v.dump_bucket ]]/[[ $v.dump_prefix ]]$name"
          echo "uploaded [[ $v.dump_bucket ]]/[[ $v.dump_prefix ]]$name ($(du -h "/tmp/gitea/$name" | cut -f1))"
          rm -f "/tmp/gitea/$name"
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
  }
}
[[- end ]]
