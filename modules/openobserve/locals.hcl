# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

locals {
  # The ID of the job and the name of its service; empty is the release.
  job     = coalesce(var.job_name, rig.release)
  cluster = var.mode == "cluster"
  mtls    = var.tls_mode == "mtls"
  http    = var.tls_mode == "none"
  scheme  = local.http ? "http" : "https"
  tls_dir = { mtls = "/secrets/mtls", secret = "/secrets/tls", none = "" }[var.tls_mode]

  host_network = var.host_network == "" ? null : var.host_network

  # The groups: one with every role (single), or one per node role
  # (cluster), in this order.
  groups = local.cluster ? [for role in ["router", "ingester", "querier", "compactor", "alertmanager"] : {
    name            = role
    role            = role
    count           = var.roles[role].count
    cpu             = var.roles[role].cpu
    memory          = var.roles[role].memory
    router          = role == "router"
    ingester_volume = role == "ingester" && var.ingester_host_volume != ""
    host_data       = role == "ingester" && var.ingester_host_volume != ""
    bootstrap       = role == "router" && var.bootstrap_enabled
    }] : [{
    name            = "openobserve"
    role            = "all"
    count           = 1
    cpu             = var.resources.cpu
    memory          = var.resources.memory
    router          = true
    ingester_volume = false
    host_data       = true
    bootstrap       = var.bootstrap_enabled
  }]

  # The secrets the tasks of a group read, with the ingest secret for the
  # group of the bootstrap task.
  secret_paths = distinct(concat(
    [var.root_secret_path],
    local.cluster ? concat(
      [var.postgres_dsn_secret_path != "" ? var.postgres_dsn_secret_path : var.postgres_secret_path, var.s3_secret_path],
      var.nats_secret_path != "" ? [var.nats_secret_path] : [],
    ) : [],
    var.tls_mode == "secret" ? [var.tls_secret_path] : [],
  ))
  bootstrap_secret_paths = distinct(concat(local.secret_paths, [var.ingest_secret_path]))

  # PostgreSQL, NATS and S3: from the native catalog unless given.
  pg_endpoint = split(":", var.postgres_endpoint)
  catalog_env = join("\n", concat(
    var.postgres_dsn_secret_path != "" ? [] : var.postgres_endpoint != "" ? [
      "ZO_META_POSTGRES_HOST=${join(":", slice(local.pg_endpoint, 0, length(local.pg_endpoint) - 1))}",
      "ZO_META_POSTGRES_PORT=${local.pg_endpoint[length(local.pg_endpoint) - 1]}",
      ] : [
      "{{- range $i, $s := nomadService \"${var.postgres_service}\" }}{{ if eq $i 0 }}",
      "ZO_META_POSTGRES_HOST={{ $s.Address }}",
      "ZO_META_POSTGRES_PORT={{ $s.Port }}",
      "{{- end }}{{ end }}",
    ],
    length(var.nats_endpoints) > 0 ? ["ZO_NATS_ADDR=${join(",", var.nats_endpoints)}"] : [
      "ZO_NATS_ADDR={{ range $i, $s := nomadService \"${var.nats_service}\" }}{{ if $i }},{{ end }}{{ $s.Address }}:{{ $s.Port }}{{ end }}",
    ],
    var.s3_endpoint != "" ? ["ZO_S3_SERVER_URL=${var.s3_endpoint}"] : [
      "{{- range $i, $s := nomadService \"${var.s3_service}\" }}{{ if eq $i 0 }}",
      "ZO_S3_SERVER_URL=${var.s3_use_ssl ? "https" : "http"}://{{ $s.Address }}:{{ $s.Port }}",
      "{{- end }}{{ end }}",
    ],
    [""],
  ))

  # The environment of OpenObserve by group, after the settings of every
  # group.
  tls_env = local.http ? {} : {
    ZO_HTTP_TLS_ENABLED           = "true"
    ZO_HTTP_TLS_CERT_PATH         = "${local.tls_dir}/cert.pem"
    ZO_HTTP_TLS_KEY_PATH          = "${local.tls_dir}/key.pem"
    ZO_HTTP_TLS_ROOT_CERTIFICATES = "native"
    ZO_GRPC_TLS_ENABLED           = "true"
    ZO_GRPC_TLS_CERT_PATH         = "${local.tls_dir}/cert.pem"
    ZO_GRPC_TLS_KEY_PATH          = "${local.tls_dir}/key.pem"
    ZO_GRPC_TLS_CERT_DOMAIN       = local.mtls ? "${local.job}-grpc.service.${runtime_env("NORCA_NAMESPACE")}.norca" : var.tls_cert_domain
    ZO_GRPC_TLS_ROOT_CERTIFICATES = "native"
    SSL_CERT_DIR                  = local.tls_dir
  }

  env = { for g in local.groups : g.name => merge(
    {
      ZO_DATA_DIR        = g.host_data ? "/data/" : "/alloc/data/openobserve/"
      ZO_ROOT_USER_EMAIL = var.root_email
      ZO_TELEMETRY       = tostring(var.telemetry_enabled)
    },
    var.web_url != "" ? { ZO_WEB_URL = var.web_url } : {},
    local.cluster ? merge(
      {
        ZO_LOCAL_MODE          = "false"
        ZO_NODE_ROLE           = g.role
        ZO_HTTP_ADDR           = runtime_env("NORCA_IP_http")
        ZO_HTTP_PORT           = runtime_env("NORCA_PORT_http")
        ZO_GRPC_ADDR           = runtime_env("NORCA_IP_grpc")
        ZO_GRPC_PORT           = runtime_env("NORCA_PORT_grpc")
        ZO_META_STORE          = "postgres"
        ZO_CLUSTER_COORDINATOR = "nats"
        ZO_QUEUE_STORE         = "nats"
        ZO_NATS_PREFIX         = var.nats_prefix
        ZO_NATS_REPLICAS       = tostring(var.nats_replicas)
        ZO_S3_PROVIDER         = "s3"
        ZO_S3_BUCKET_NAME      = var.s3_bucket
        ZO_S3_REGION_NAME      = var.s3_region
      },
      var.postgres_dsn_secret_path == "" ? { ZO_META_POSTGRES_USER = var.postgres_user, ZO_META_POSTGRES_DBNAME = var.postgres_database } : {},
      ) : {
      ZO_LOCAL_MODE         = "true"
      ZO_LOCAL_MODE_STORAGE = "disk"
      ZO_META_STORE         = "sqlite"
      ZO_HTTP_PORT          = "5080"
      ZO_GRPC_PORT          = "5081"
    },
    local.tls_env,
    # The router proxies HTTP to the advertised IP address of a node, which
    # the certificate does not name: that hop is encrypted but not
    # verified. Internal gRPC is verified (ZO_GRPC_TLS_CERT_DOMAIN).
    !local.http && local.cluster ? { ZO_HTTP_TLS_SKIP_VERIFY = "true" } : {},
    var.extra_env,
  ) }
}

# The bootstrap task: the organizations, the ingest service account and its
# credentials in the secret store, the S3 bucket (cluster). It talks to the
# OpenObserve instance of its own allocation.
locals {
  bucket = local.cluster && var.s3_create_bucket

  s3_env = var.s3_endpoint != "" ? "S3_URL=${var.s3_endpoint}\n" : join("\n", [
    "{{- range $i, $s := nomadService \"${var.s3_service}\" }}{{ if eq $i 0 }}",
    "S3_URL=${var.s3_use_ssl ? "https" : "http"}://{{ $s.Address }}:{{ $s.Port }}",
    "{{- end }}{{ end }}",
    "",
  ])

  bootstrap_connect = {
    mtls   = <<-EOT
      # The instance's workload certificate names the service, not the
      # address: connect by name, verified with the trust bundle.
      base="https://$OO_NAME:$OO_PORT"
      oocurl() { curl -sS --cacert "$NORCA_SECRETS_DIR/mtls/bundle.pem" --resolve "$OO_NAME:$OO_PORT:$OO_IP" "$@"; }
    EOT
    secret = <<-EOT
      # The certificate of the secret need not name the node address; the
      # connection stays on the node.
      base="https://$OO_IP:$OO_PORT"
      oocurl() { curl -sS -k "$@"; }
    EOT
    none   = <<-EOT
      base="http://$OO_IP:$OO_PORT"
      oocurl() { curl -sS "$@"; }
    EOT
  }

  bootstrap_bucket = <<-EOT

    # The S3 bucket (S3 CreateBucket signed with AWS SigV4).
    code=$(curl -sS -o /tmp/s3 -w '%%{http_code}' -X PUT --aws-sigv4 "aws:amz:${var.s3_region}:s3" \
      --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" "$S3_URL/${var.s3_bucket}")
    case "$code" in
      200) log "bucket ${var.s3_bucket} created" ;;
      409) log "bucket ${var.s3_bucket} exists" ;;
      *) log "bucket ${var.s3_bucket}: HTTP $code"; cat /tmp/s3; exit 1 ;;
    esac
  EOT

  bootstrap_script = join("", [
    <<-EOT
      #!/bin/sh
      set -u
      log() { echo "bootstrap: $*"; }
    EOT
    ,
    local.bootstrap_connect[var.tls_mode],
    <<-EOT
      # api <user:password> <method> <path> [json]: the body goes to
      # /tmp/body, the HTTP status code to stdout.
      api() {
        if [ $# -ge 4 ]; then
          oocurl -o /tmp/body -w '%%{http_code}' -u "$1" -X "$2" -H 'Content-Type: application/json' --data "$4" "$base$3"
        else
          oocurl -o /tmp/body -w '%%{http_code}' -u "$1" -X "$2" "$base$3"
        fi
      }
      root="$ROOT_EMAIL:$ROOT_PASSWORD"

      i=0
      until [ "$(oocurl -o /dev/null -w '%%{http_code}' "$base/healthz" 2>/dev/null)" = 200 ]; do
        i=$((i + 1))
        if [ "$i" -ge 120 ]; then log "OpenObserve is not ready after 10 minutes"; exit 1; fi
        sleep 5
      done
    EOT
    ,
    local.bucket ? local.bootstrap_bucket : "",
    <<-EOT

      # Organizations: "default" comes with the root user; another one is
      # created by a first ingestion (the API would give it a random
      # identifier).
      code=$(api "$root" GET /api/organizations)
      [ "$code" = 200 ] || { log "listing the organizations: HTTP $code"; cat /tmp/body; exit 1; }
      cp /tmp/body /tmp/orgs
      for org in $ORGANIZATIONS; do
        if grep -q "\"identifier\":\"$org\"" /tmp/orgs; then
          log "organization $org exists"
          continue
        fi
        code=$(api "$root" POST "/api/$org/norca_bootstrap/_json" '[{"message":"organization created by the Norca openobserve pack"}]')
        [ "$code" = 200 ] || { log "creating organization $org: HTTP $code"; cat /tmp/body; exit 1; }
        log "organization $org created"
      done

      # The ingest credentials in the secret store still work: done.
      if [ -n "$${INGEST_USERNAME:-}" ] && [ -n "$${INGEST_PASSWORD:-}" ]; then
        code=$(api "$INGEST_USERNAME:$INGEST_PASSWORD" GET "/api/$INGEST_ORG/streams")
        if [ "$code" = 200 ]; then
          log "the ingest credentials in $INGEST_PATH work"
          exit 0
        fi
        log "the ingest credentials in $INGEST_PATH don't work (HTTP $code): new token"
      fi

      # The service account (an existing one is kept) and a new token.
      code=$(api "$root" POST "/api/$INGEST_ORG/service_accounts" \
        "{\"email\":\"$INGEST_ACCOUNT\",\"first_name\":\"otel\",\"last_name\":\"collector\"}")
      log "service account $INGEST_ACCOUNT: HTTP $code (an existing account answers with an error)"
      code=$(api "$root" PUT "/api/$INGEST_ORG/service_accounts/$INGEST_ACCOUNT?rotateToken=true" '{}')
      [ "$code" = 200 ] || { log "token of $INGEST_ACCOUNT: HTTP $code"; cat /tmp/body; exit 1; }
      token=$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' /tmp/body)
      rm -f /tmp/body
      [ -n "$token" ] || { log "no token in the response"; exit 1; }

      # Into the secret store, through the task API with the workload
      # identity of this task.
      code=$(curl -sS -o /tmp/put -w '%%{http_code}' --unix-socket "$NORCA_SECRETS_DIR/api.sock" -X PUT \
        -H "X-Nomad-Token: $NORCA_TOKEN" \
        --data "{\"Items\":{\"username\":\"$INGEST_ACCOUNT\",\"password\":\"$token\",\"organization\":\"$INGEST_ORG\"}}" \
        "http://localhost/v1/secret/$INGEST_PATH?namespace=$NORCA_NAMESPACE")
      token=""
      if [ "$code" != 200 ]; then
        log "writing $INGEST_PATH failed: HTTP $code $(cat /tmp/put)"
        log "bind the ACL policy of the pack (acl_policy_enabled), or rotate the token by hand and store it:"
        log "  curl -u <root> -X PUT -H 'Content-Type: application/json' --data '{}' $base/api/$INGEST_ORG/service_accounts/$INGEST_ACCOUNT?rotateToken=true"
        log "  norca secret put -namespace $NORCA_NAMESPACE $INGEST_PATH username=$INGEST_ACCOUNT organization=$INGEST_ORG password=-"
        exit 1
      fi
      log "ingest credentials of $INGEST_ACCOUNT stored in $INGEST_PATH"
    EOT
  ])
}
