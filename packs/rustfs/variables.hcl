# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# ---------------------------------------------------------------------------
# Job and placement
# ---------------------------------------------------------------------------

variable "job_name" {
  description = "Name of the job. Empty uses the pack name (\"rustfs\"). It is also the name of the S3 service (<job>) and of the console service (<job>-console)."
  type        = string
  default     = ""

  validation {
    pattern = "^([a-zA-Z0-9][a-zA-Z0-9_-]{0,62})?$"
  }
}

variable "namespace" {
  description = "Namespace of the job and of its secret. Empty leaves it to the namespace of the release."
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

  validation {
    min_items       = 1
    item_min_length = 1
  }
}

variable "node_pool" {
  description = "Node pool of the job. Empty uses the default node pool."
  type        = string
  default     = ""
}

variable "constraints" {
  description = "Extra placement constraints of the job, e.g. [{attribute = \"$${meta.storage}\", operator = \"=\", value = \"backup\"}]."
  type = list(object({
    attribute = string
    operator  = string
    value     = string
  }))
  default = []
}

# ---------------------------------------------------------------------------
# Mode
# ---------------------------------------------------------------------------

variable "mode" {
  description = "single (default): one server with one drive (the host volume). distributed: one server on each node of nodes, the drives erasure coded across them."
  type        = string
  default     = "single"

  ui {
    options = ["single", "distributed"]
  }
}

variable "nodes" {
  description = "Distributed mode: the addresses of the nodes that run a server, as the other servers reach them (at least 2; 4 or more for erasure coding that survives the loss of a node). The job places one server on each of them and lists them in RUSTFS_VOLUMES; the list can't change without a new cluster (expansion with a server pool is not supported by the pack)."
  type        = list(string)
  default     = []

  validation {
    unique       = true
    item_pattern = "^[a-zA-Z0-9.:\\[\\]-]+$"
  }
}

variable "node_address_attribute" {
  description = "Distributed mode: the node attribute holding the address listed in nodes. It places the servers on those nodes and tells each server which endpoint is its own (RUSTFS_LOCAL_ENDPOINT_HOST)."
  type        = string
  default     = "$${attr.unique.network.ip-address}"

  validation {
    pattern = "^\\$\\{(attr|meta)\\.[^}]+\\}$"
  }
}

# ---------------------------------------------------------------------------
# Image and task
# ---------------------------------------------------------------------------

variable "image" {
  description = "RustFS image (docker driver). The official image, pinned to a release; mirror it for air-gapped clusters."
  type        = string
  default     = "docker.io/rustfs/rustfs:1.0.1"

  validation {
    min_length = 1
  }
}

variable "image_digest" {
  description = "Digest of the image (sha256:...), appended as image@digest to pin the content. Empty uses the tag alone."
  type        = string
  default     = ""

  validation {
    pattern = "^(sha256:[a-f0-9]{64})?$"
  }
}

variable "user" {
  description = "User (uid[:gid]) of the RustFS container. Empty uses the user of the image (10001:10001), which must own the host volume directory."
  type        = string
  default     = ""

  validation {
    pattern = "^([0-9]+(:[0-9]+)?|[a-z_][a-z0-9_-]*)?$"
  }
}

variable "resources" {
  description = "Resources of a RustFS server: cpu in MHz, memory in MB."
  type = object({
    cpu    = number
    memory = number
  })
  default = {
    cpu    = 500
    memory = 1024
  }
}

variable "log_level" {
  description = "RustFS log level (RUSTFS_OBS_LOGGER_LEVEL): error, warn, info, debug or trace. Logs go to the task's stdout."
  type        = string
  default     = "warn"

  ui {
    options = ["error", "warn", "info", "debug", "trace"]
  }
}

variable "extra_env" {
  description = "Further RustFS environment variables (RUSTFS_*), e.g. {RUSTFS_SERVER_DOMAINS = \"s3.example.com\"}. Never put credentials here: they come from the secret."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Metrics and traces (OTLP)
# ---------------------------------------------------------------------------

variable "metrics_enabled" {
  description = "Send the metrics of RustFS over OTLP/HTTP to otlp_endpoint (RUSTFS_OBS_METRIC_ENDPOINT), by default the OpenTelemetry Collector of the otel-collector pack on the same node. RustFS has no Prometheus endpoint; it only pushes OTLP. Logs stay in the task's stdout."
  type        = bool
  default     = false
}

variable "traces_enabled" {
  description = "Also send traces over OTLP/HTTP to otlp_endpoint (RUSTFS_OBS_TRACE_ENDPOINT). RustFS samples every request (RUSTFS_OBS_SAMPLE_RATIO 1.0) unless extra_env lowers it."
  type        = bool
  default     = false
}

variable "otlp_endpoint" {
  description = "Base URL of the OTLP/HTTP receiver (/v1/metrics and /v1/traces are appended). The default is the collector of the otel-collector pack on the node of the server (host port 4318 on the node address)."
  type        = string
  default     = "http://$${attr.unique.network.ip-address}:4318"

  validation {
    pattern = "^https?://[^/?#]+(/[^?#]*)?$"
  }
}

# ---------------------------------------------------------------------------
# Storage, network, S3
# ---------------------------------------------------------------------------

variable "host_volume" {
  description = "Client host volume with the data (client { host_volume \"rustfs\" { path = \"/srv/rustfs\" } }), mounted at /data. The directory must be writable by the container user (10001 by default)."
  type        = string
  default     = "rustfs"

  validation {
    min_length = 1
  }
}

variable "s3_port" {
  description = "Static port of the S3 API on the node: the Norca servers reach the store at http://<node address>:<port> (the endpoint of the backup destination)."
  type        = number
  default     = 9000

  validation {
    integer = true
    min     = 1
    max     = 65535
  }
}

variable "console_enabled" {
  description = "Enable the RustFS web console (with the same root credentials). Off by default: the backup store needs only the S3 API."
  type        = bool
  default     = false
}

variable "console_port" {
  description = "Static port of the console on the node, with console_enabled."
  type        = number
  default     = 9001

  validation {
    integer = true
    min     = 1
    max     = 65535
  }
}

variable "host_network" {
  description = "Client host_network to bind the ports to. Empty uses the default address of the node."
  type        = string
  default     = ""
}

variable "s3_region" {
  description = "Region name of the S3 API (RUSTFS_REGION). Use the same value as region in the backup destination and in the AWS SigV4 scope of curl."
  type        = string
  default     = "us-east-1"

  validation {
    min_length = 1
  }
}

# ---------------------------------------------------------------------------
# Credentials and buckets
# ---------------------------------------------------------------------------

variable "secret_path" {
  description = "Path of the secret in the built-in secret store with the root credentials, items access_key and secret_key (the secret of the job's namespace). The job's secret_access grant covers only this path."
  type        = string
  default     = "rustfs/root"

  validation {
    min_length = 1
  }
}

variable "buckets" {
  description = "Buckets a poststart task creates once the store is ready (S3 CreateBucket, signed by curl; existing buckets are left alone), e.g. [\"norca-backup\"]. Empty creates none."
  type        = list(string)
  default     = []

  validation {
    unique       = true
    item_pattern = "^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$"
  }
}

# ---------------------------------------------------------------------------
# Updates and checks
# ---------------------------------------------------------------------------

variable "startup_timeout" {
  description = "Time a server has after its start to pass the startup check (distributed servers wait for the quorum of their peers)."
  type        = string
  default     = "3m"

  validation {
    pattern = "^[0-9]+(s|m|h)$"
  }
}

variable "healthy_deadline" {
  description = "Deadline of a server to become healthy during updates and migrations."
  type        = string
  default     = "10m"

  validation {
    pattern = "^[0-9]+(s|m|h)$"
  }
}

# ---------------------------------------------------------------------------
# Rules: conditions on the items of lists and maps and across variables,
# checked before rendering by the CLI and by the servers that render the pack.
# ---------------------------------------------------------------------------

rule "constraints" {
  condition     = alltrue([for x in var.constraints : x.attribute != null && x.operator != ""])
  error_message = "constraints: each item needs attribute and operator; operator must not be empty."
}

rule "resources" {
  condition = (
    floor(var.resources.cpu) == var.resources.cpu &&
    var.resources.cpu >= 100 &&
    floor(var.resources.memory) == var.resources.memory &&
    var.resources.memory >= 256
  )
  error_message = "resources: needs cpu and memory; cpu must be at least 100; memory must be at least 256."
}

rule "extra_env" {
  condition = alltrue([
    for k in keys(var.extra_env) :
    (
      can(regex("^RUSTFS_[A-Z0-9_]+$", k)) &&
      !contains(["RUSTFS_ACCESS_KEY", "RUSTFS_SECRET_KEY", "RUSTFS_ACCESS_KEY_FILE", "RUSTFS_SECRET_KEY_FILE", "RUSTFS_ROOT_USER", "RUSTFS_ROOT_PASSWORD", "RUSTFS_VOLUMES", "RUSTFS_ADDRESS"], k)
    )
  ])
  error_message = "extra_env: the names must match ^RUSTFS_[A-Z0-9_]+$ and not be RUSTFS_ACCESS_KEY, RUSTFS_SECRET_KEY, RUSTFS_ACCESS_KEY_FILE, RUSTFS_SECRET_KEY_FILE, RUSTFS_ROOT_USER, RUSTFS_ROOT_PASSWORD, RUSTFS_VOLUMES, RUSTFS_ADDRESS."
}

rule "nodes" {
  condition     = var.mode != "distributed" || length(var.nodes) >= 2
  error_message = "nodes needs at least 2 items when mode is distributed."
}
