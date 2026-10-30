# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# ---------------------------------------------------------------------------
# Job and placement
# ---------------------------------------------------------------------------

variable "job_name" {
  description = "Name of the job. Empty uses the pack name (\"traefik\"). It also names the services (<job>: the admin port with /ping, <job>-<entrypoint>: the entrypoints)."
  type        = string
  default     = ""

  ui {
    tab   = "general"
    group = "Job"
  }

  validation {
    pattern = "^([a-zA-Z0-9][a-zA-Z0-9_-]{0,52})?$"
  }
}

variable "namespace" {
  description = "Namespace of the job. Empty leaves it to the namespace of the release."
  type        = string
  default     = ""

  ui {
    tab    = "general"
    group  = "Job"
    widget = "namespace-select"
  }
}

variable "region" {
  description = "Region of the job. Empty leaves it to the region of the release."
  type        = string
  default     = ""

  ui {
    tab    = "general"
    group  = "Job"
    widget = "region-select"
  }
}

variable "datacenters" {
  description = "Datacenters of the job."
  type        = list(string)
  default     = ["*"]

  ui {
    tab   = "general"
    group = "Placement"
  }

  validation {
    min_items       = 1
    item_min_length = 1
  }
}

variable "node_pool" {
  description = "Node pool of the job, e.g. the pool of the edge nodes that the clients reach. Empty uses the default node pool."
  type        = string
  default     = ""

  ui {
    tab    = "general"
    group  = "Placement"
    widget = "node-pool-select"
  }
}

variable "job_type" {
  description = "\"service\": count instances on different nodes; \"system\": an instance on every node of the node pool and datacenters (edge nodes behind DNS round robin or an external load balancer)."
  type        = string
  default     = "service"

  ui {
    tab     = "general"
    group   = "Placement"
    options = ["service", "system"]
  }
}

variable "count" {
  description = "Instances of a service job, on different nodes."
  type        = number
  default     = 2

  ui {
    tab     = "general"
    group   = "Placement"
    widget  = "slider"
    show_if = { field = "job_type", equals = "service" }
  }

  validation {
    min     = 1
    max     = 9
    integer = true
  }
}

variable "constraints" {
  description = "Extra placement constraints, e.g. {attribute = \"$${meta.edge}\", operator = \"=\", value = \"true\"}."
  type = list(object({
    attribute = string
    operator  = optional(string, "=")
    value     = optional(string, "")
  }))
  default = []

  ui {
    tab          = "general"
    group        = "Placement"
    item_options = { operator = ["=", "!=", ">", ">=", "<", "<=", "regexp", "set_contains", "set_contains_any", "is_set", "is_not_set", "version", "semver"] }
  }
}

# ---------------------------------------------------------------------------
# Image and task
# ---------------------------------------------------------------------------

variable "image" {
  description = "Image of Traefik Proxy (MIT), the official one by default."
  type        = string
  default     = "docker.io/library/traefik:v3.7.16"

  ui {
    tab   = "general"
    group = "Image"
  }

  validation {
    min_length = 1
  }
}

variable "image_digest" {
  description = "Digest of the image (sha256:...), appended as image@digest to pin the content. Empty uses the tag alone."
  type        = string
  default     = ""

  ui {
    tab   = "general"
    group = "Image"
  }

  validation {
    pattern = "^(sha256:[a-f0-9]{64})?$"
  }
}

variable "log_level" {
  description = "Log level of Traefik."
  type        = string
  default     = "INFO"

  ui {
    tab     = "general"
    group   = "Logs"
    options = ["DEBUG", "INFO", "WARN", "ERROR"]
  }
}

variable "access_log" {
  description = "Write an access log line per request to the task's stdout."
  type        = bool
  default     = false

  ui {
    tab   = "general"
    group = "Logs"
  }
}

# ---------------------------------------------------------------------------
# Entrypoints: the ports open to the outside
# ---------------------------------------------------------------------------

variable "entrypoints" {
  description = "The ports Traefik listens on. protocol: http (HTTP/1.1, WebSocket, h2c), https (the same over TLS with the certificates of the TLS tab, HTTP/2 and gRPC), tcp (raw TCP: databases, TLS passthrough by SNI), udp. redirect_to names an https entrypoint that the requests of an http one are redirected to. Names: letters, digits, - and _."
  type = list(object({
    name        = string
    port        = number
    protocol    = optional(string, "http")
    redirect_to = optional(string, "")
  }))
  default = [
    { name = "web", port = 80, protocol = "http", redirect_to = "websecure" },
    { name = "websecure", port = 443, protocol = "https", redirect_to = "" },
  ]

  ui {
    tab          = "entrypoints"
    group        = "Entrypoints"
    widget       = "object-list"
    item_options = { protocol = ["http", "https", "tcp", "udp"] }
  }

  validation {
    min_items = 1
  }
}

variable "network_mode" {
  description = "\"host\": Traefik binds the entrypoint ports on the node itself (the client addresses stay visible, UDP works); \"bridge\": the ports are mapped into the allocation's network namespace."
  type        = string
  default     = "host"

  ui {
    tab     = "entrypoints"
    group   = "Network"
    options = ["host", "bridge"]
  }
}

variable "host_network" {
  description = "Client host network the entrypoint ports are bound to, e.g. the public interface of the edge nodes. Empty: the default network of the node."
  type        = string
  default     = ""

  ui {
    tab   = "entrypoints"
    group = "Network"
  }
}

variable "admin_port" {
  description = "Port of the internal entrypoint \"traefik\": /ping (the health check), the dashboard and /metrics when enabled. Keep it closed to the outside (firewall, a private host_network)."
  type        = number
  default     = 8080

  ui {
    tab   = "entrypoints"
    group = "Admin"
  }

  validation {
    min     = 1
    max     = 65535
    integer = true
  }
}

variable "dashboard" {
  description = "Serve the read-only dashboard and API on the admin port (http://<node>:<admin_port>/dashboard/)."
  type        = bool
  default     = false

  ui {
    tab   = "entrypoints"
    group = "Admin"
  }
}

variable "metrics" {
  description = "Prometheus metrics on the admin port (/metrics)."
  type        = bool
  default     = false

  ui {
    tab   = "entrypoints"
    group = "Admin"
  }
}

# ---------------------------------------------------------------------------
# TLS: certificates from the secret store
# ---------------------------------------------------------------------------

variable "tls_certificates" {
  description = "Secrets of the built-in secret store with a certificate each (in the namespace of the job): the item cert (PEM, the chain) and the item key (PEM). Traefik picks the certificate by the SNI name of a connection. norca secret put traefik/certs/example-com cert=@fullchain.pem key=@privkey.pem"
  type        = list(string)
  default     = []

  ui {
    tab   = "tls"
    group = "Certificates"
  }

  validation {
    item_pattern = "^[a-zA-Z0-9_~/-]+$"
  }
}

variable "tls_default_certificate" {
  description = "Secret with the certificate for connections without a matching SNI name (items cert and key). Empty: the first of tls_certificates, or Traefik's self-signed one."
  type        = string
  default     = ""

  ui {
    tab   = "tls"
    group = "Certificates"
  }

  validation {
    pattern = "^[a-zA-Z0-9_~/-]*$"
  }
}

variable "tls_cert_item" {
  description = "Item of the certificate in the secrets."
  type        = string
  default     = "cert"

  ui {
    tab   = "tls"
    group = "Certificates"
  }
}

variable "tls_key_item" {
  description = "Item of the private key in the secrets."
  type        = string
  default     = "key"

  ui {
    tab   = "tls"
    group = "Certificates"
  }
}

variable "tls_min_version" {
  description = "Lowest TLS version of the https entrypoints."
  type        = string
  default     = "VersionTLS12"

  ui {
    tab     = "tls"
    group   = "Options"
    options = ["VersionTLS12", "VersionTLS13"]
  }
}

# ---------------------------------------------------------------------------
# Routing: the native catalog and static file configuration
# ---------------------------------------------------------------------------

variable "catalog_enabled" {
  description = "Route to the services of Norca's native catalog by their tags (the Nomad provider of Traefik), e.g. tags = [\"traefik.enable=true\", \"traefik.http.routers.app.rule=Host(`app.example.com`)\"]."
  type        = bool
  default     = true

  ui {
    tab   = "routing"
    group = "Catalog"
  }
}

variable "catalog_namespaces" {
  description = "Namespaces whose services Traefik routes to. Other namespaces than the job's need the ACL policy that the output of the pack prints."
  type        = list(string)
  default     = ["default"]

  ui {
    tab     = "routing"
    group   = "Catalog"
    show_if = "catalog_enabled"
  }

  validation {
    min_items       = 1
    item_min_length = 1
  }
}

variable "exposed_by_default" {
  description = "Route to every service of the namespaces; off: only to those with the tag traefik.enable=true."
  type        = bool
  default     = false

  ui {
    tab     = "routing"
    group   = "Catalog"
    show_if = "catalog_enabled"
  }
}

variable "nomad_address" {
  description = "Address of the Norca API for the catalog. Empty: the task API socket of the allocation (unix://, with the workload identity of the task, no TLS settings needed)."
  type        = string
  default     = ""

  ui {
    tab     = "routing"
    group   = "Catalog"
    show_if = "catalog_enabled"
  }
}

variable "dynamic_config" {
  description = "Static routes in Traefik's dynamic configuration (YAML of the file provider): routers, services and middlewares to fixed backends, for HTTP, WebSocket, gRPC (h2c://), TCP and UDP. Applied without a restart. See the examples of the pack registry."
  type        = string
  default     = ""

  ui {
    tab    = "routing"
    group  = "Static configuration"
    widget = "code"
  }
}

# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------

variable "resources" {
  description = "CPU (MHz) and memory (MB) of Traefik."
  type = object({
    cpu    = number
    memory = number
  })
  default = {
    cpu    = 200
    memory = 256
  }

  ui {
    tab = "resources"
  }
}
