# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0
[[- $v := vars . ]]
[[- template "rustfs.validate" . ]]
[[- $job := $v.job_name ]][[ if eq $job "" ]][[ $job = (meta "pack.name" .) ]][[ end ]]
[[- $image := $v.image ]][[ if ne $v.image_digest "" ]][[ $image = printf "%s@%s" $v.image $v.image_digest ]][[ end ]]
[[- $distributed := eq $v.mode "distributed" ]]
[[- $port := int $v.s3_port ]]
[[- $endpoints := list ]][[ range $n := $v.nodes ]][[ $endpoints = append $endpoints (printf "http://%s:%d/data" $n $port) ]][[ end ]]

# RustFS, an S3-compatible object store (Apache-2.0, https://rustfs.com),
# rendered by the rustfs pack as the store of the Norca backups. The nodes pull
# the official image; Norca does not ship it. Keep the backups of a cluster
# outside the cluster they protect: run this job in another region or cluster
# than the servers it backs up, or use an external S3 store in production.
job [[ $job | quote ]] {
[[- if ne $v.region "" ]]
  region      = [[ $v.region | quote ]]
[[- end ]]
[[- if ne $v.namespace "" ]]
  namespace   = [[ $v.namespace | quote ]]
[[- end ]]
  datacenters = [[ $v.datacenters | toStringList ]]
[[- if ne $v.node_pool "" ]]
  node_pool   = [[ $v.node_pool | quote ]]
[[- end ]]
  type = "service"
[[- range $c := $v.constraints ]]

  constraint {
    attribute = [[ $c.attribute | quote ]]
    operator  = [[ $c.operator | quote ]]
[[- if ne $c.value "" ]]
    value     = [[ $c.value | quote ]]
[[- end ]]
  }
[[- end ]]

  group "rustfs" {
    count = [[ if $distributed ]][[ len $v.nodes ]][[ else ]]1[[ end ]]
[[- if $distributed ]]

    # One server on each node of the endpoint list.
    constraint {
      attribute = [[ $v.node_address_attribute | quote ]]
      operator  = "set_contains_any"
      value     = [[ join "," $v.nodes | quote ]]
    }

    constraint {
      operator = "distinct_hosts"
      value    = "true"
    }

    # Drains and evictions take down one server at a time, so the erasure
    # sets keep their quorum.
    disruption {
      max_unavailable = "1"
    }
[[- else ]]

    # A single instance: evictions (norca alloc stop -respect-disruption) are
    # refused, and a node drain moves it only when its deadline is reached.
    disruption {
      min_healthy = "1"
    }
[[- end ]]

    # One server at a time; a server counts as healthy when its readiness
    # check passes.
    update {
      max_parallel      = 1
      health_check      = "checks"
      min_healthy_time  = "10s"
      healthy_deadline  = [[ $v.healthy_deadline | quote ]]
      progress_deadline = "0"
      auto_revert       = false
    }

    migrate {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "10s"
      healthy_deadline = [[ $v.healthy_deadline | quote ]]
    }

    # Static ports on the node, the same inside the container: the Norca
    # servers (and the other RustFS servers) reach the S3 API at
    # http://<node address>:[[ $port ]].
    network {
      port "s3" {
        static = [[ $port ]]
        to     = [[ $port ]]
[[- if ne $v.host_network "" ]]
        host_network = [[ $v.host_network | quote ]]
[[- end ]]
      }
[[- if $v.console_enabled ]]

      port "console" {
        static = [[ $v.console_port ]]
        to     = [[ $v.console_port ]]
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

    # The tasks read only the secret with the root credentials.
    secret_access {
      path = [[ $v.secret_path | quote ]]
    }

    service {
      name     = [[ $job | quote ]]
      provider = "nomad"
      port     = "s3"

      check {
        name            = "startup"
        role            = "startup"
        type            = "http"
        path            = "/health/live"
        interval        = "5s"
        timeout         = "2s"
        startup_timeout = [[ $v.startup_timeout | quote ]]
      }

      # Ready when the server can serve requests (storage, IAM and lock
      # quorum); during startup it answers 503.
      check {
        name     = "readiness"
        role     = "readiness"
        type     = "http"
        path     = "/health/ready"
        interval = "10s"
        timeout  = "3s"
      }

      check {
        name     = "liveness"
        role     = "liveness"
        type     = "http"
        path     = "/health/live"
        interval = "15s"
        timeout  = "3s"
      }
    }
[[- if $v.console_enabled ]]

    service {
      name     = "[[ $job ]]-console"
      provider = "nomad"
      port     = "console"

      check {
        name     = "readiness"
        role     = "readiness"
        type     = "http"
        path     = "/rustfs/console/health"
        interval = "15s"
        timeout  = "3s"
      }
    }
[[- end ]]

    task "rustfs" {
      driver = "docker"

      config {
        image = [[ $image | quote ]]
        ports = ["s3"[[ if $v.console_enabled ]], "console"[[ end ]]]
      }
[[- if ne $v.user "" ]]

      user = [[ $v.user | quote ]]
[[- end ]]

      volume_mount {
        volume      = "data"
        destination = "/data"
      }
[[ template "rustfs.credentials" . ]]

      # Listen address, drives, S3 region, console; an empty log directory
      # sends the logs to stdout (the task logs).
      env {
        RUSTFS_ADDRESS                  = ":[[ $port ]]"
[[- if $distributed ]]
        RUSTFS_VOLUMES                  = [[ join " " $endpoints | quote ]]
        RUSTFS_LOCAL_ENDPOINT_HOST      = [[ $v.node_address_attribute | quote ]]
[[- else ]]
        RUSTFS_VOLUMES                  = "/data"
[[- end ]]
        RUSTFS_REGION                   = [[ $v.s3_region | quote ]]
        RUSTFS_CONSOLE_ENABLE           = "[[ $v.console_enabled ]]"
[[- if $v.console_enabled ]]
        RUSTFS_CONSOLE_ADDRESS          = ":[[ $v.console_port ]]"
[[- end ]]
        RUSTFS_OBS_LOGGER_LEVEL         = [[ $v.log_level | quote ]]
        RUSTFS_OBS_LOG_DIRECTORY        = ""
[[- if or $v.metrics_enabled $v.traces_enabled ]]
        # OTLP/HTTP export of the signals below only (a per-signal endpoint
        # is used as it is; logs keep going to stdout).
        RUSTFS_OBS_SERVICE_NAME         = [[ $job | quote ]]
[[- end ]]
[[- if $v.metrics_enabled ]]
        RUSTFS_OBS_METRIC_ENDPOINT      = "[[ trimSuffix "/" $v.otlp_endpoint ]]/v1/metrics"
[[- end ]]
[[- if $v.traces_enabled ]]
        RUSTFS_OBS_TRACE_ENDPOINT       = "[[ trimSuffix "/" $v.otlp_endpoint ]]/v1/traces"
[[- end ]]
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
[[- if $v.buckets ]]

    # Creates the buckets once the store is ready (S3 CreateBucket, signed
    # with AWS SigV4 by the curl of the RustFS image). Existing buckets are
    # left alone; Norca never creates its backup bucket itself.
    task "create-buckets" {
      driver = "docker"

      lifecycle {
        hook    = "poststart"
        sidecar = false
      }

      config {
        image      = [[ $image | quote ]]
        entrypoint = ["/bin/sh", "/local/create-buckets.sh"]
      }
[[ template "rustfs.credentials" . ]]

      template {
        destination = "local/create-buckets.sh"
        data        = <<-EOF
          #!/bin/sh
          set -u
          s3="http://127.0.0.1:[[ $port ]]"
          i=0
          until curl -fsS -o /dev/null "$s3/health/ready"; do
            i=$((i + 1))
            if [ "$i" -ge 120 ]; then echo "RustFS is not ready after 10 minutes" >&2; exit 1; fi
            sleep 5
          done
          for bucket in [[ join " " $v.buckets ]]; do
            code=$(curl -sS -o /tmp/response -w '%%{http_code}' -X PUT \
              --aws-sigv4 "aws:amz:[[ $v.s3_region ]]:s3" \
              --user "$RUSTFS_ACCESS_KEY:$RUSTFS_SECRET_KEY" "$s3/$bucket")
            case "$code" in
              200) echo "bucket $bucket created" ;;
              409) echo "bucket $bucket exists" ;;
              *) echo "bucket $bucket: HTTP $code" >&2; cat /tmp/response >&2; exit 1 ;;
            esac
          done
        EOF
      }

      restart {
        attempts = 3
        delay    = "15s"
        mode     = "fail"
      }

      resources {
        cpu    = 50
        memory = 32
      }
    }
[[- end ]]
  }
}
