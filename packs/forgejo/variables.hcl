# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# ---------------------------------------------------------------------------
# Job and placement
# ---------------------------------------------------------------------------

variable "job_name" {
  description = "Name of the job. Empty uses the pack name (\"forgejo\"). It also names the services (<job>, <job>-ssh) and the dump job (<job>-dump)."
  type        = string
  default     = ""
}

variable "namespace" {
  description = "Namespace of the jobs and of their secrets. Empty leaves it to the namespace of the release."
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
  description = "Extra placement constraints of the jobs, e.g. [{attribute = \"$${meta.forgejo}\", operator = \"=\", value = \"true\"}]. The host volume already ties Forgejo to the nodes that have it; give exactly one node the volume (SQLite, one instance)."
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
  description = "Forgejo image (docker driver): the official rootless image, pinned to a release of the v15 LTS line. data.forgejo.org/forgejo/forgejo is the official mirror."
  type        = string
  default     = "codeberg.org/forgejo/forgejo:15.0.10-rootless"
}

variable "image_digest" {
  description = "Digest of the image (sha256:...), appended as image@digest to pin the content. Empty uses the tag alone."
  type        = string
  default     = ""
}

variable "uid" {
  description = "User id the container runs as (1000, user git of the rootless image). It owns the host volume directory and the secret files the pack renders."
  type        = number
  default     = 1000
}

variable "gid" {
  description = "Group id the container runs as (1000 in the rootless image)."
  type        = number
  default     = 1000
}

variable "resources" {
  description = "Resources of the Forgejo task: cpu in MHz, memory in MB."
  type = object({
    cpu    = number
    memory = number
  })
  default = {
    cpu    = 1000
    memory = 1024
  }
}

variable "host_volume" {
  description = "Client host volume mounted at /var/lib/gitea: app.ini, the SQLite database, the git repositories, indexes and logs (client { host_volume \"forgejo\" { path = \"/srv/forgejo\" } }), owned by uid:gid."
  type        = string
  default     = "forgejo"
}

variable "startup_timeout" {
  description = "Time Forgejo has after its start to pass the startup check (database migrations after an upgrade can take a while)."
  type        = string
  default     = "5m"
}

variable "healthy_deadline" {
  description = "Deadline of the instance to become healthy during updates and migrations."
  type        = string
  default     = "10m"
}

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

variable "domain" {
  description = "Host name of Forgejo (DOMAIN, SSH_DOMAIN): the name clients and the Docker daemons of the nodes use, and the registry host of the container images (<domain>[:port]/<owner>/<image>:<tag>)."
  type        = string
  default     = "forgejo.internal"
}

variable "http_port" {
  description = "Static HTTP(S) port on the node (inside the container Forgejo listens on 3000). With 443 (https) or 80 (http) the URLs and image names carry no port."
  type        = number
  default     = 3000
}

variable "root_url" {
  description = "ROOT_URL, the public URL of Forgejo. Empty: <scheme>://<domain>[:<http_port>]/. Behind a TLS-terminating proxy, set it to the URL of the proxy, e.g. https://forgejo.internal/."
  type        = string
  default     = ""
}

variable "host_network" {
  description = "Client host_network to bind the ports to. Empty uses the default address of the node."
  type        = string
  default     = ""
}

variable "app_name" {
  description = "APP_NAME, the title of the web interface."
  type        = string
  default     = "Forgejo"
}

variable "disable_registration" {
  description = "Disable self-registration ([service] DISABLE_REGISTRATION): an internal forge creates its users through the admin."
  type        = bool
  default     = true
}

variable "require_signin_view" {
  description = "Require a sign-in to view anything ([service] REQUIRE_SIGNIN_VIEW)."
  type        = bool
  default     = false
}

variable "extra_env" {
  description = "Further Forgejo settings as FORGEJO__<section>__<KEY> environment variables, e.g. {FORGEJO__mailer__ENABLED = \"false\"}. Never put secrets here: the keys, credentials and certificates come from the secret store."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# HTTPS and SSH
# ---------------------------------------------------------------------------

variable "https_enabled" {
  description = "Serve HTTPS from Forgejo itself ([server] PROTOCOL = https) with the certificate and key of tls_secret_path. Docker needs HTTPS for a registry on another host; the alternative is a TLS-terminating proxy (root_url)."
  type        = bool
  default     = false
}

variable "tls_secret_path" {
  description = "Secret with the PEM certificate (item cert, with the chain) and key (item key) for https_enabled."
  type        = string
  default     = "forgejo/tls"
}

variable "ssh_enabled" {
  description = "Enable git over SSH (the built-in SSH server of the rootless image, port 2222 in the container)."
  type        = bool
  default     = true
}

variable "ssh_port" {
  description = "Static SSH port on the node, shown in the clone URLs (SSH_PORT)."
  type        = number
  default     = 2222
}

# ---------------------------------------------------------------------------
# Secrets and the initial admin
# ---------------------------------------------------------------------------

variable "keys_secret_path" {
  description = "Secret with the keys of Forgejo, items secret_key, internal_token, jwt_secret and lfs_jwt_secret (generate them with forgejo generate secret ...). They are read from files (SECRET_KEY_URI, ...), not written into app.ini."
  type        = string
  default     = "forgejo/keys"
}

variable "admin_enabled" {
  description = "Create the initial admin with a poststart task once Forgejo is ready (skipped when the user exists)."
  type        = bool
  default     = true
}

variable "admin_username" {
  description = "User name of the initial admin (\"admin\" is reserved by Forgejo)."
  type        = string
  default     = "forgejo-admin"
}

variable "admin_email" {
  description = "Email address of the initial admin."
  type        = string
  default     = "forgejo-admin@forgejo.internal"
}

variable "admin_secret_path" {
  description = "Secret with the password of the initial admin (item password)."
  type        = string
  default     = "forgejo/admin"
}

# ---------------------------------------------------------------------------
# Object storage (RustFS)
# ---------------------------------------------------------------------------

variable "storage_enabled" {
  description = "Keep packages (container images), LFS objects, attachments, avatars, repository archives and Actions data in S3 ([storage] STORAGE_TYPE = minio), e.g. the RustFS of the rustfs pack. Git repositories and SQLite stay on the host volume. false keeps everything on the host volume."
  type        = bool
  default     = true
}

variable "storage_service" {
  description = "Service of the S3 store in the native catalog, in the namespace of the job (the rustfs pack registers \"rustfs\"). The address of its first instance becomes MINIO_ENDPOINT. Ignored when storage_endpoint is set."
  type        = string
  default     = "rustfs"
}

variable "storage_endpoint" {
  description = "host:port of the S3 store, instead of the catalog lookup (a store in another namespace, region or outside the cluster)."
  type        = string
  default     = ""
}

variable "storage_use_ssl" {
  description = "Connect to the S3 store over HTTPS (MINIO_USE_SSL)."
  type        = bool
  default     = false
}

variable "storage_bucket" {
  description = "Bucket of the Forgejo objects (MINIO_BUCKET), one directory per kind (packages/, lfs/, attachments/, ...). Forgejo creates it at its start if its key may, or create it with the rustfs pack (buckets)."
  type        = string
  default     = "forgejo"
}

variable "storage_region" {
  description = "Region of the S3 store (MINIO_LOCATION); s3_region of the rustfs pack."
  type        = string
  default     = "us-east-1"
}

variable "storage_secret_path" {
  description = "Secret with the S3 credentials, items access_key and secret_key: a dedicated RustFS user limited to the buckets of Forgejo, or the root credentials. They reach Forgejo as AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (its credential chain), not through app.ini."
  type        = string
  default     = "forgejo/storage"
}

# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------

variable "metrics_enabled" {
  description = "Serve Prometheus metrics on /metrics ([metrics] ENABLED) and tag the HTTP service with \"metrics\", so that the otel-collector pack scrapes it."
  type        = bool
  default     = false
}

variable "metrics_token_secret_path" {
  description = "Secret with the bearer token of /metrics (item token), passed as [metrics] TOKEN through FORGEJO__metrics__TOKEN__FILE. The otel-collector pack reads the same secret. Empty serves /metrics without a token."
  type        = string
  default     = "forgejo/metrics"
}

# ---------------------------------------------------------------------------
# Dumps
# ---------------------------------------------------------------------------

variable "dump_enabled" {
  description = "Add a periodic batch job (<job>-dump) that runs forgejo dump (database, repositories, custom files; the objects in S3 are skipped) and uploads it to dump_bucket. Needs storage_enabled."
  type        = bool
  default     = false
}

variable "dump_cron" {
  description = "Schedule of the dump job (cron syntax, UTC)."
  type        = string
  default     = "0 3 * * *"
}

variable "dump_bucket" {
  description = "Bucket of the dumps (it must exist; e.g. buckets of the rustfs pack). Keep it apart from storage_bucket and expire old dumps with a lifecycle rule."
  type        = string
  default     = "forgejo-dump"
}

variable "dump_prefix" {
  description = "Prefix of the dump objects in dump_bucket."
  type        = string
  default     = "forgejo/"
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
