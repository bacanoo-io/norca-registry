# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# ---------------------------------------------------------------------------
# Job and placement
# ---------------------------------------------------------------------------

variable "job_name" {
  description = "Name of the job. Empty uses the pack name (\"postgres\"). It is also the name of the service in the native catalog (<job>) and names the dump job (<job>-dump)."
  type        = string
  default     = ""
}

variable "namespace" {
  description = "Namespace of the jobs and of their secrets. Empty leaves it to the namespace of the release. Clients that find the server through the catalog (nomadService) must run in the same namespace."
  type        = string
  default     = ""
}

variable "region" {
  description = "Region of the jobs. Empty leaves it to the region of the release."
  type        = string
  default     = ""
}

variable "datacenters" {
  description = "Datacenters of the jobs."
  type        = list(string)
  default     = ["*"]
}

variable "node_pool" {
  description = "Node pool of the jobs. Empty uses the default node pool."
  type        = string
  default     = ""
}

variable "constraints" {
  description = "Extra placement constraints of the jobs, e.g. [{attribute = \"$${meta.postgres}\", operator = \"=\", value = \"true\"}]. The host volume already ties the server to the nodes that have it; give exactly one node the volume."
  type = list(object({
    attribute = string
    operator  = string
    value     = string
  }))
  default = []
}

# ---------------------------------------------------------------------------
# Image and task
# ---------------------------------------------------------------------------

variable "image" {
  description = "PostgreSQL image (docker driver): the official image, pinned to a minor release. PostgreSQL 15 or newer (the setup task uses the getenv command of psql). A new major version needs a dump and restore (or pg_upgrade); the pack does not upgrade the data directory."
  type        = string
  default     = "docker.io/library/postgres:18.6"
}

variable "image_digest" {
  description = "Digest of the image (sha256:...), appended as image@digest to pin the content. Empty uses the tag alone."
  type        = string
  default     = ""
}

variable "uid" {
  description = "User id the server runs as: 999 (postgres) in the Debian images, 70 in the Alpine images. It must own the host volume directory."
  type        = number
  default     = 999
}

variable "gid" {
  description = "Group id the server runs as (999 in the Debian images, 70 in the Alpine images)."
  type        = number
  default     = 999
}

variable "resources" {
  description = "Resources of the server: cpu in MHz, memory in MB. Raise shared_buffers (settings) with the memory."
  type = object({
    cpu    = number
    memory = number
  })
  default = {
    cpu    = 500
    memory = 1024
  }
}

variable "host_volume" {
  description = "Client host volume with the data, mounted at /var/lib/postgresql. The image keeps its data directory below it (PGDATA /var/lib/postgresql/18/docker for PostgreSQL 18, a directory per major version). The directory must be owned by uid:gid."
  type        = string
  default     = "postgres"
}

variable "port" {
  description = "Static port of the server on the node (5432 in the container)."
  type        = number
  default     = 5432
}

variable "host_network" {
  description = "Client host_network to bind the port to. Empty uses the default address of the node."
  type        = string
  default     = ""
}

variable "settings" {
  description = "Server settings passed as postgres -c <name>=<value>, e.g. {max_connections = \"200\", shared_buffers = \"256MB\"}. Never put secrets here."
  type        = map(string)
  default     = {}
}

variable "startup_timeout" {
  description = "Time the server has after its start to pass the startup check (crash recovery after an unclean stop can take a while)."
  type        = string
  default     = "5m"
}

variable "healthy_deadline" {
  description = "Deadline of the server to become healthy during updates and migrations."
  type        = string
  default     = "10m"
}

# ---------------------------------------------------------------------------
# Users and databases (passwords from the built-in secret store)
# ---------------------------------------------------------------------------

variable "superuser" {
  description = "Name of the superuser the image creates at the first start (POSTGRES_USER)."
  type        = string
  default     = "postgres"
}

variable "superuser_secret_path" {
  description = "Secret with the password of the superuser (item password), read from a file (POSTGRES_PASSWORD_FILE) at the first start, and by the setup and dump tasks."
  type        = string
  default     = "postgres/superuser"
}

variable "databases" {
  description = "Application databases the setup task creates (idempotent: existing ones are kept), each with an owner role whose password is the item password of secret_path, set again at every run (a new secret version changes it). E.g. [{name = \"openobserve\", user = \"openobserve\", secret_path = \"postgres/openobserve\"}]."
  type = list(object({
    name        = string
    user        = string
    secret_path = string
  }))
  default = []
}

variable "monitoring_enabled" {
  description = "Create a monitoring role with the pg_monitor role (read-only statistics, for the postgresql receiver of the otel-collector pack). Its password is the item password of monitoring_secret_path; while that secret does not exist the setup task skips the role."
  type        = bool
  default     = true
}

variable "monitoring_user" {
  description = "Name of the monitoring role."
  type        = string
  default     = "monitoring"
}

variable "monitoring_secret_path" {
  description = "Secret with the password of the monitoring role (item password). The otel-collector pack reads the same secret (postgres_secret_path)."
  type        = string
  default     = "postgres/monitoring"
}

# ---------------------------------------------------------------------------
# TLS
# ---------------------------------------------------------------------------

variable "tls_mode" {
  description = "TLS of the server: \"none\" (default, plain connections), \"mtls\" (Norca's workload certificate of the service, mtls { mode = \"app\" }: valid for <job>.service.<namespace>.nomad, renewed automatically) or \"secret\" (the PEM certificate and key of tls_secret_path). Non-TLS connections stay allowed unless tls_required."
  type        = string
  default     = "none"
}

variable "tls_secret_path" {
  description = "Secret with the PEM certificate (item cert, with the chain) and key (item key) for tls_mode = \"secret\"."
  type        = string
  default     = "postgres/tls"
}

variable "tls_required" {
  description = "Reject TCP connections without TLS (pg_hba hostssl instead of host). The setup and dump tasks connect with sslmode=require then."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Dumps
# ---------------------------------------------------------------------------

variable "dump_enabled" {
  description = "Add a periodic batch job (<job>-dump) that runs pg_dumpall (all databases and roles, gzip) and uploads the file to dump_bucket with an S3 PUT signed by curl."
  type        = bool
  default     = false
}

variable "dump_cron" {
  description = "Schedule of the dump job (cron syntax, UTC)."
  type        = string
  default     = "0 2 * * *"
}

variable "dump_bucket" {
  description = "Bucket of the dumps (it must exist; e.g. buckets of the rustfs pack). Expire old dumps with a lifecycle rule."
  type        = string
  default     = "postgres-dump"
}

variable "dump_prefix" {
  description = "Prefix of the dump objects in dump_bucket."
  type        = string
  default     = "postgres/"
}

variable "dump_storage_service" {
  description = "Service of the S3 store in the native catalog, in the namespace of the job (the rustfs pack registers \"rustfs\"). Ignored when dump_storage_endpoint is set."
  type        = string
  default     = "rustfs"
}

variable "dump_storage_endpoint" {
  description = "host:port of the S3 store, instead of the catalog lookup (a store in another namespace, region or outside the cluster)."
  type        = string
  default     = ""
}

variable "dump_storage_use_ssl" {
  description = "Upload over HTTPS."
  type        = bool
  default     = false
}

variable "dump_storage_region" {
  description = "Region of the S3 store (the AWS SigV4 scope; s3_region of the rustfs pack)."
  type        = string
  default     = "us-east-1"
}

variable "dump_storage_secret_path" {
  description = "Secret with the S3 credentials of the uploads, items access_key and secret_key."
  type        = string
  default     = "postgres/dump-storage"
}

variable "dump_upload_image" {
  description = "Image of the upload task (curl 7.75 or newer for --aws-sigv4)."
  type        = string
  default     = "docker.io/curlimages/curl:8.22.0"
}

variable "dump_resources" {
  description = "Resources of the dump task: cpu in MHz, memory in MB."
  type = object({
    cpu    = number
    memory = number
  })
  default = {
    cpu    = 500
    memory = 512
  }
}
