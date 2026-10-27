# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# ---------------------------------------------------------------------------
# Job and placement
# ---------------------------------------------------------------------------

variable "job_name" {
  description = "Name of the job. Empty uses the pack name (\"openobserve\"). It is also the name of the HTTP service (<job>: the UI, the API and OTLP/HTTP) and prefixes the gRPC service (<job>-grpc)."
  type        = string
  default     = ""
}

variable "namespace" {
  description = "Namespace of the job, its secrets and its ACL policy. Empty uses \"default\" for the ACL policy and leaves the job to the namespace of the release; set it when the release goes to another namespace. The otel-collector pack must run in the same namespace (it reads the ingest secret)."
  type        = string
  default     = ""
}

variable "region" {
  description = "Region of the job. Empty leaves it to the region of the release."
  type        = string
  default     = ""
}

variable "datacenters" {
  description = "Datacenters of the job."
  type        = list(string)
  default     = ["*"]
}

variable "node_pool" {
  description = "Node pool of the job. Empty uses the default node pool."
  type        = string
  default     = ""
}

variable "constraints" {
  description = "Extra placement constraints of the job, e.g. [{attribute = \"$${meta.observability}\", operator = \"=\", value = \"true\"}]."
  type = list(object({
    attribute = string
    operator  = string
    value     = string
  }))
  default = []
}

# ---------------------------------------------------------------------------
# Image
# ---------------------------------------------------------------------------

variable "image" {
  description = "OpenObserve image (docker driver): the official open source image (AGPL-3.0), pinned to a release. public.ecr.aws/zinclabs/openobserve is the same image."
  type        = string
  default     = "docker.io/openobserve/openobserve:v1.0.4"
}

variable "image_digest" {
  description = "Digest of the image (sha256:...), appended as image@digest to pin the content. Empty uses the tag alone."
  type        = string
  default     = ""
}

variable "extra_env" {
  description = "Further OpenObserve settings (ZO_*), e.g. {ZO_COMPACT_DATA_RETENTION_DAYS = \"30\"}. Never put secrets here: credentials come from the secret store."
  type        = map(string)
  default     = {}
}

variable "telemetry_enabled" {
  description = "ZO_TELEMETRY: let OpenObserve send anonymous usage data to its vendor (its default is on). Off for an internal installation."
  type        = bool
  default     = false
}

variable "web_url" {
  description = "ZO_WEB_URL: the URL users open, used in links (alerts, reports). Empty keeps OpenObserve's default."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Mode
# ---------------------------------------------------------------------------

variable "mode" {
  description = "single (default): one instance with every role, SQLite metadata and the data on a host volume. cluster: a group per node role (router, ingester, querier, compactor, alertmanager) with PostgreSQL metadata, NATS as coordinator and the data in S3 (RustFS)."
  type        = string
  default     = "single"
}

variable "http_port" {
  description = "Static HTTP(S) port of the UI, the API and OTLP/HTTP on the node: of the instance (single) or of the routers (cluster)."
  type        = number
  default     = 5080
}

variable "grpc_port" {
  description = "Static gRPC port (OTLP/gRPC) on the node: of the instance (single) or of the routers (cluster). The other cluster nodes use dynamic ports."
  type        = number
  default     = 5081
}

variable "host_network" {
  description = "Client host_network of the ports. Empty uses the default address of the node."
  type        = string
  default     = ""
}

variable "startup_timeout" {
  description = "Time an instance has after its start to pass the startup check."
  type        = string
  default     = "5m"
}

variable "healthy_deadline" {
  description = "Deadline of an instance to become healthy during updates and migrations."
  type        = string
  default     = "10m"
}

# ---------------------------------------------------------------------------
# Single mode
# ---------------------------------------------------------------------------

variable "host_volume" {
  description = "Single mode: client host volume with the data (SQLite, WAL, parquet files), mounted at /data. The image runs as root."
  type        = string
  default     = "openobserve"
}

variable "resources" {
  description = "Single mode: resources of the instance, cpu in MHz, memory in MB."
  type = object({
    cpu    = number
    memory = number
  })
  default = {
    cpu    = 1000
    memory = 2048
  }
}

# ---------------------------------------------------------------------------
# Cluster mode: node roles
# ---------------------------------------------------------------------------

variable "roles" {
  description = "Cluster mode: instances and resources of each node role (ZO_NODE_ROLE): router (UI, API, proxies to the others), ingester (writes, WAL), querier (searches), compactor (merges files, retention), alertmanager (alerts, reports, scheduled jobs). Every role needs at least one instance."
  type = map(object({
    count  = number
    cpu    = number
    memory = number
  }))
  default = {
    router = {
      count  = 2
      cpu    = 500
      memory = 1024
    }
    ingester = {
      count  = 2
      cpu    = 1000
      memory = 2048
    }
    querier = {
      count  = 2
      cpu    = 1000
      memory = 2048
    }
    compactor = {
      count  = 1
      cpu    = 500
      memory = 1024
    }
    alertmanager = {
      count  = 1
      cpu    = 250
      memory = 512
    }
  }
}

variable "cluster_disk_mb" {
  description = "Cluster mode: size of the sticky ephemeral disk of every instance (WAL of the ingesters, caches), in MB."
  type        = number
  default     = 10240
}

variable "ingester_host_volume" {
  description = "Cluster mode: client host volume for the WAL of the ingesters instead of the ephemeral disk (survives the loss of the allocation). Empty uses the ephemeral disk."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Cluster mode: PostgreSQL, NATS, S3
# ---------------------------------------------------------------------------

variable "postgres_service" {
  description = "Cluster mode: service of PostgreSQL in the native catalog, in the namespace of the job (the postgres pack registers \"postgres\"). Ignored when postgres_endpoint or postgres_dsn_secret_path is set."
  type        = string
  default     = "postgres"
}

variable "postgres_endpoint" {
  description = "Cluster mode: host:port of PostgreSQL instead of the catalog lookup."
  type        = string
  default     = ""
}

variable "postgres_database" {
  description = "Cluster mode: database of the metadata (ZO_META_POSTGRES_DBNAME)."
  type        = string
  default     = "openobserve"
}

variable "postgres_user" {
  description = "Cluster mode: role of OpenObserve in PostgreSQL (ZO_META_POSTGRES_USER), the owner of postgres_database."
  type        = string
  default     = "openobserve"
}

variable "postgres_secret_path" {
  description = "Cluster mode: secret with the password of postgres_user (item password), e.g. the secret of the database entry of the postgres pack."
  type        = string
  default     = "postgres/openobserve"
}

variable "postgres_dsn_secret_path" {
  description = "Cluster mode: secret with a complete DSN (item dsn, postgres://user:password@host:port/db?sslmode=...) for an external PostgreSQL. Set, it replaces the catalog lookup, postgres_endpoint, postgres_user and postgres_secret_path."
  type        = string
  default     = ""
}

variable "nats_service" {
  description = "Cluster mode: client service of NATS in the native catalog, in the namespace of the job (the nats pack registers \"nats\"). Every instance becomes an entry of ZO_NATS_ADDR. JetStream must be enabled. Ignored when nats_endpoints is set."
  type        = string
  default     = "nats"
}

variable "nats_endpoints" {
  description = "Cluster mode: host:port of the NATS servers instead of the catalog lookup."
  type        = list(string)
  default     = []
}

variable "nats_secret_path" {
  description = "Cluster mode: secret with the NATS user name and password of OpenObserve (items username, password): its user of the nats pack with auth_mode = \"userpass\", e.g. users = [{name = \"openobserve\", account = \"OPENOBSERVE\"}] (a dedicated account). OpenObserve supports user/password authentication only (no token, NKey or TLS settings). Empty connects without authentication (NATS with auth_mode = \"none\")."
  type        = string
  default     = "openobserve/nats"
}

variable "nats_replicas" {
  description = "Cluster mode: replicas of the JetStream KV buckets and streams of OpenObserve (ZO_NATS_REPLICAS): at most the number of NATS servers; fixed once the buckets exist."
  type        = number
  default     = 3
}

variable "nats_prefix" {
  description = "Cluster mode: prefix of the JetStream buckets and streams (ZO_NATS_PREFIX): different installations sharing one NATS need different prefixes."
  type        = string
  default     = "o2_"
}

variable "s3_service" {
  description = "Cluster mode: service of the S3 store in the native catalog, in the namespace of the job (the rustfs pack registers \"rustfs\"). The address of its first instance becomes ZO_S3_SERVER_URL. Ignored when s3_endpoint is set."
  type        = string
  default     = "rustfs"
}

variable "s3_endpoint" {
  description = "Cluster mode: URL of the S3 store (http(s)://host:port) instead of the catalog lookup."
  type        = string
  default     = ""
}

variable "s3_use_ssl" {
  description = "Cluster mode: connect to the S3 store of the catalog lookup over HTTPS."
  type        = bool
  default     = false
}

variable "s3_bucket" {
  description = "Cluster mode: bucket of the data (ZO_S3_BUCKET_NAME). OpenObserve does not create it; the bootstrap task does (s3_create_bucket), or the buckets variable of the rustfs pack."
  type        = string
  default     = "openobserve"
}

variable "s3_region" {
  description = "Cluster mode: region of the S3 store (ZO_S3_REGION_NAME; s3_region of the rustfs pack)."
  type        = string
  default     = "us-east-1"
}

variable "s3_secret_path" {
  description = "Cluster mode: secret with the S3 credentials, items access_key and secret_key: a RustFS user limited to s3_bucket, or the root credentials."
  type        = string
  default     = "openobserve/s3"
}

variable "s3_create_bucket" {
  description = "Cluster mode: let the bootstrap task create s3_bucket (S3 CreateBucket signed by curl; an existing bucket is left alone)."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# TLS
# ---------------------------------------------------------------------------

variable "tls_mode" {
  description = "TLS of HTTP and gRPC: \"mtls\" (default: Norca's workload certificates, mtls { mode = \"app\" } on the services, valid for <job>.service.<namespace>.nomad and <job>-grpc.service.<namespace>.nomad, trusted through the trust bundle of the region), \"secret\" (the PEM certificate, key and CA of tls_secret_path) or \"none\" (plain HTTP and gRPC)."
  type        = string
  default     = "mtls"
}

variable "tls_secret_path" {
  description = "tls_mode = \"secret\": secret with the PEM certificate (item cert, with the chain), key (item key) and the CA that issued it (item ca)."
  type        = string
  default     = "openobserve/tls"
}

variable "tls_cert_domain" {
  description = "tls_mode = \"secret\", cluster mode: the DNS name in the certificate the nodes verify on internal gRPC calls (ZO_GRPC_TLS_CERT_DOMAIN). Every node uses the same certificate."
  type        = string
  default     = ""
}

variable "tls_restart_interval" {
  description = "Deprecated and ignored since pack version 0.2.0, removed in 0.3.0: the client restarts the OpenObserve tasks after a renewal of the workload certificate or a CA rotation (mtls { change_mode = \"restart\" }), so the periodic restarts of the tls-restart sidecar are gone. Still accepted so that existing variable files keep working."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Users, organizations, ingest credentials
# ---------------------------------------------------------------------------

variable "root_email" {
  description = "Email of the root user (ZO_ROOT_USER_EMAIL, lower case), created at the first start with the password of root_secret_path."
  type        = string
  default     = "root@openobserve.internal"
}

variable "root_secret_path" {
  description = "Secret with the password of the root user (item password: 8-128 characters with a lower-case and an upper-case letter, a digit and a special character, or OpenObserve refuses to start). Used at the first start only; afterwards the password is stored in OpenObserve."
  type        = string
  default     = "openobserve/root"
}

variable "bootstrap_enabled" {
  description = "Run the bootstrap task after every start (idempotent): the organizations, the ingest service account and its credentials in the secret store, the S3 bucket in cluster mode."
  type        = bool
  default     = true
}

variable "bootstrap_image" {
  description = "Image of the bootstrap task (curl and a shell; the OpenObserve image has neither)."
  type        = string
  default     = "docker.io/curlimages/curl:8.22.0"
}

variable "organizations" {
  description = "Organizations (identifiers) the bootstrap task makes sure of. \"default\" exists with the root user; others are created by a first ingestion of one record into the stream norca_bootstrap."
  type        = list(string)
  default     = ["default"]
}

variable "ingest_organization" {
  description = "Organization of the ingest service account; the collectors write into it."
  type        = string
  default     = "default"
}

variable "ingest_service_account" {
  description = "Email of the service account of the collectors, created in ingest_organization by the bootstrap task."
  type        = string
  default     = "otel-collector@openobserve.internal"
}

variable "ingest_secret_path" {
  description = "Secret the bootstrap task writes the ingest credentials into (items username, password: the token of the service account, organization) and the otel-collector pack reads. Writing needs the ACL policy of the pack (acl_policy_enabled) when ACLs are enabled."
  type        = string
  default     = "openobserve/ingest"
}

variable "acl_policy_enabled" {
  description = "Install the ACL policy of the pack, bound to its job: the bootstrap task writes the ingest secret. Disable it on agents without ACLs (dev agents), where policies can't be written."
  type        = bool
  default     = true
}
