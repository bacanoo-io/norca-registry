[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]

[[- /* Checks the variables the schema can't express. */ -]]
[[- define "oo.validate" -]]
[[- $v := vars . -]]
[[- if eq $v.mode "cluster" -]]
[[- range $r := list "router" "ingester" "querier" "compactor" "alertmanager" -]]
[[- if not (hasKey $v.roles $r) ]][[ fail (printf "roles needs an entry for every node role, %q is missing" $r) ]][[ end -]]
[[- end -]]
[[- if gt (int $v.nats_replicas) 5 ]][[ fail "nats_replicas can be at most 5 (JetStream)" ]][[ end -]]
[[- end -]]
[[- if and (eq $v.tls_mode "secret") (eq $v.mode "cluster") (eq $v.tls_cert_domain "") -]]
[[- fail "tls_mode = \"secret\" in cluster mode needs tls_cert_domain (the name of the certificate the nodes verify on gRPC)" -]]
[[- end -]]
[[- if not (has $v.ingest_organization $v.organizations) -]]
[[- fail "ingest_organization must be one of organizations" -]]
[[- end -]]
[[- if eq $v.http_port $v.grpc_port ]][[ fail "grpc_port must differ from http_port" ]][[ end -]]
[[- end -]]

[[- /* region, namespace, datacenters, node_pool and the extra constraints of the job. */ -]]
[[- define "oo.location" -]]
[[- $v := vars . ]]
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
[[- range $c := $v.constraints ]]

  constraint {
    attribute = [[ $c.attribute | quote ]]
    operator  = [[ $c.operator | quote ]]
[[- if ne $c.value "" ]]
    value     = [[ $c.value | quote ]]
[[- end ]]
  }
[[- end ]]
[[- end -]]

[[- /* The secret paths the tasks of a group read (call with dict "ctx" . "bootstrap" bool). */ -]]
[[- define "oo.secret_access" -]]
[[- $v := vars .ctx ]]
[[- $paths := list $v.root_secret_path ]]
[[- if eq $v.mode "cluster" ]]
[[- if ne $v.postgres_dsn_secret_path "" ]][[ $paths = append $paths $v.postgres_dsn_secret_path ]][[ else ]][[ $paths = append $paths $v.postgres_secret_path ]][[ end ]]
[[- $paths = append $paths $v.s3_secret_path ]]
[[- if ne $v.nats_secret_path "" ]][[ $paths = append $paths $v.nats_secret_path ]][[ end ]]
[[- end ]]
[[- if eq $v.tls_mode "secret" ]][[ $paths = append $paths $v.tls_secret_path ]][[ end ]]
[[- if .bootstrap ]][[ $paths = append $paths $v.ingest_secret_path ]][[ end ]]
[[- range $p := $paths | uniq ]]

    secret_access {
      path = [[ $p | quote ]]
    }
[[- end ]]
[[- end -]]

[[- /* The checks of the HTTP service of a group: HTTP on /healthz without TLS. Norca's
native HTTP checks verify certificates against the system CAs and connect to the
instance address, which the workload certificate doesn't name, so with TLS they are
TCP checks. */ -]]
[[- define "oo.checks" -]]
[[- $v := vars . ]]
[[- $http := eq $v.tls_mode "none" ]]

      check {
        name            = "startup"
        role            = "startup"
[[- if $http ]]
        type            = "http"
        path            = "/healthz"
[[- else ]]
        type            = "tcp"
[[- end ]]
        interval        = "5s"
        timeout         = "2s"
        startup_timeout = [[ $v.startup_timeout | quote ]]
      }

      check {
        name     = "readiness"
        role     = "readiness"
[[- if $http ]]
        type     = "http"
        path     = "/healthz"
[[- else ]]
        type     = "tcp"
[[- end ]]
        interval = "10s"
        timeout  = "3s"
      }

      check {
        name     = "liveness"
        role     = "liveness"
[[- if $http ]]
        type     = "http"
        path     = "/healthz"
[[- else ]]
        type     = "tcp"
[[- end ]]
        interval = "15s"
        timeout  = "3s"

        check_restart {
          limit = 3
          grace = "60s"
        }
      }
[[- end -]]

[[- /* The OpenObserve task of a group (call with dict "ctx" . "role" <role or "all">). */ -]]
[[- define "oo.task" -]]
[[- $v := vars .ctx ]]
[[- $role := .role ]]
[[- $job := $v.job_name ]][[ if eq $job "" ]][[ $job = (meta "pack.name" .ctx) ]][[ end ]]
[[- $image := $v.image ]][[ if ne $v.image_digest "" ]][[ $image = printf "%s@%s" $v.image $v.image_digest ]][[ end ]]
[[- $cluster := eq $v.mode "cluster" ]]
[[- $hostData := or (not $cluster) (and (eq $role "ingester") (ne $v.ingester_host_volume "")) ]]
[[- $tlsDir := "" ]][[ if eq $v.tls_mode "mtls" ]][[ $tlsDir = "/secrets/mtls" ]][[ else if eq $v.tls_mode "secret" ]][[ $tlsDir = "/secrets/tls" ]][[ end ]]

    task "openobserve" {
      driver = "docker"

      config {
        image = [[ $image | quote ]]
[[- if $cluster ]]
        # Host networking: a node advertises ZO_HTTP_ADDR/ZO_GRPC_ADDR, the
        # address it binds to, to the other nodes.
        network_mode = "host"
[[- else ]]
        ports = ["http", "grpc"]
[[- end ]]
      }
[[- if $hostData ]]

      volume_mount {
        volume      = "data"
        destination = "/data"
      }
[[- end ]]

      # The password of the root user (used when the root user is created).
      secret "root" {
        path = [[ $v.root_secret_path | quote ]]

        env {
          ZO_ROOT_USER_PASSWORD = "password"
        }
      }
[[- if $cluster ]]
[[- if ne $v.postgres_dsn_secret_path "" ]]

      secret "postgres" {
        path = [[ $v.postgres_dsn_secret_path | quote ]]

        env {
          ZO_META_POSTGRES_DSN = "dsn"
        }
      }
[[- else ]]

      secret "postgres" {
        path = [[ $v.postgres_secret_path | quote ]]

        env {
          ZO_META_POSTGRES_PASSWORD = "password"
        }
      }
[[- end ]]

      secret "s3" {
        path = [[ $v.s3_secret_path | quote ]]

        env {
          ZO_S3_ACCESS_KEY = "access_key"
          ZO_S3_SECRET_KEY = "secret_key"
        }
      }
[[- if ne $v.nats_secret_path "" ]]

      secret "nats" {
        path = [[ $v.nats_secret_path | quote ]]

        env {
          ZO_NATS_USER     = "username"
          ZO_NATS_PASSWORD = "password"
        }
      }
[[- end ]]

      # PostgreSQL, NATS and S3: from the native catalog unless given. A
      # change (an instance moved) restarts the node.
      template {
        destination = "secrets/catalog.env"
        env         = true
        change_mode = "restart"
        splay       = "1m"
        data        = <<-EOF
[[- if eq $v.postgres_dsn_secret_path "" ]]
[[- if ne $v.postgres_endpoint "" ]]
[[- $pg := splitList ":" $v.postgres_endpoint ]]
          ZO_META_POSTGRES_HOST=[[ initial $pg | join ":" ]]
          ZO_META_POSTGRES_PORT=[[ last $pg ]]
[[- else ]]
          {{- range $i, $s := nomadService "[[ $v.postgres_service ]]" }}{{ if eq $i 0 }}
          ZO_META_POSTGRES_HOST={{ $s.Address }}
          ZO_META_POSTGRES_PORT={{ $s.Port }}
          {{- end }}{{ end }}
[[- end ]]
[[- end ]]
[[- if $v.nats_endpoints ]]
          ZO_NATS_ADDR=[[ join "," $v.nats_endpoints ]]
[[- else ]]
          ZO_NATS_ADDR={{ range $i, $s := nomadService "[[ $v.nats_service ]]" }}{{ if $i }},{{ end }}{{ $s.Address }}:{{ $s.Port }}{{ end }}
[[- end ]]
[[- if ne $v.s3_endpoint "" ]]
          ZO_S3_SERVER_URL=[[ $v.s3_endpoint ]]
[[- else ]]
          {{- range $i, $s := nomadService "[[ $v.s3_service ]]" }}{{ if eq $i 0 }}
          ZO_S3_SERVER_URL=[[ if $v.s3_use_ssl ]]https[[ else ]]http[[ end ]]://{{ $s.Address }}:{{ $s.Port }}
          {{- end }}{{ end }}
[[- end ]]
        EOF
      }
[[- end ]]
[[- if eq $v.tls_mode "secret" ]]
[[- range $item := list "cert" "key" "ca" ]]

      template {
        data        = "{{ with nomadSecret \"[[ $v.tls_secret_path ]]\" }}{{ .[[ $item ]] }}{{ end }}"
        destination = "secrets/tls/[[ $item ]].pem"
        perms       = "0400"
        change_mode = "restart"
      }
[[- end ]]
[[- end ]]

      env {
        ZO_DATA_DIR          = "[[ if $hostData ]]/data/[[ else ]]/alloc/data/openobserve/[[ end ]]"
        ZO_ROOT_USER_EMAIL   = [[ $v.root_email | quote ]]
        ZO_TELEMETRY         = "[[ $v.telemetry_enabled ]]"
[[- if ne $v.web_url "" ]]
        ZO_WEB_URL           = [[ $v.web_url | quote ]]
[[- end ]]
[[- if $cluster ]]
        ZO_LOCAL_MODE          = "false"
        ZO_NODE_ROLE           = [[ $role | quote ]]
        ZO_HTTP_ADDR           = "${NOMAD_IP_http}"
        ZO_HTTP_PORT           = "${NOMAD_PORT_http}"
        ZO_GRPC_ADDR           = "${NOMAD_IP_grpc}"
        ZO_GRPC_PORT           = "${NOMAD_PORT_grpc}"
        ZO_META_STORE          = "postgres"
[[- if eq $v.postgres_dsn_secret_path "" ]]
        ZO_META_POSTGRES_USER   = [[ $v.postgres_user | quote ]]
        ZO_META_POSTGRES_DBNAME = [[ $v.postgres_database | quote ]]
[[- end ]]
        ZO_CLUSTER_COORDINATOR = "nats"
        ZO_QUEUE_STORE         = "nats"
        ZO_NATS_PREFIX         = [[ $v.nats_prefix | quote ]]
        ZO_NATS_REPLICAS       = "[[ $v.nats_replicas ]]"
        ZO_S3_PROVIDER         = "s3"
        ZO_S3_BUCKET_NAME      = [[ $v.s3_bucket | quote ]]
        ZO_S3_REGION_NAME      = [[ $v.s3_region | quote ]]
[[- else ]]
        ZO_LOCAL_MODE         = "true"
        ZO_LOCAL_MODE_STORAGE = "disk"
        ZO_META_STORE         = "sqlite"
        ZO_HTTP_PORT          = "5080"
        ZO_GRPC_PORT          = "5081"
[[- end ]]
[[- if ne $v.tls_mode "none" ]]
        # TLS on HTTP and gRPC. The trust anchors of the clients inside
        # OpenObserve (internal gRPC, the router's proxy) are the system CAs
        # plus the certificates in [[ $tlsDir ]] (SSL_CERT_DIR, read by
        # rustls-native-certs): [[ if eq $v.tls_mode "mtls" ]]the trust bundle of the region[[ else ]]the CA of the secret[[ end ]].
        ZO_HTTP_TLS_ENABLED            = "true"
        ZO_HTTP_TLS_CERT_PATH          = "[[ $tlsDir ]]/cert.pem"
        ZO_HTTP_TLS_KEY_PATH           = "[[ $tlsDir ]]/key.pem"
        ZO_HTTP_TLS_ROOT_CERTIFICATES  = "native"
        ZO_GRPC_TLS_ENABLED            = "true"
        ZO_GRPC_TLS_CERT_PATH          = "[[ $tlsDir ]]/cert.pem"
        ZO_GRPC_TLS_KEY_PATH           = "[[ $tlsDir ]]/key.pem"
        ZO_GRPC_TLS_CERT_DOMAIN        = "[[ if eq $v.tls_mode "mtls" ]][[ $job ]]-grpc.service.${NOMAD_NAMESPACE}.nomad[[ else ]][[ $v.tls_cert_domain ]][[ end ]]"
        ZO_GRPC_TLS_ROOT_CERTIFICATES  = "native"
        SSL_CERT_DIR                   = "[[ $tlsDir ]]"
[[- if $cluster ]]
        # The router proxies HTTP to the advertised IP address of a node,
        # which the certificate does not name: that hop is encrypted but not
        # verified. Internal gRPC is verified (ZO_GRPC_TLS_CERT_DOMAIN).
        ZO_HTTP_TLS_SKIP_VERIFY        = "true"
[[- end ]]
[[- end ]]
[[- range $k, $val := $v.extra_env ]]
        [[ $k ]] = [[ $val | quote ]]
[[- end ]]
      }

      kill_timeout = "30s"

      resources {
[[- if $cluster ]]
        cpu    = [[ (get $v.roles $role).cpu ]]
        memory = [[ (get $v.roles $role).memory ]]
[[- else ]]
        cpu    = [[ $v.resources.cpu ]]
        memory = [[ $v.resources.memory ]]
[[- end ]]
      }
    }
[[- end -]]
