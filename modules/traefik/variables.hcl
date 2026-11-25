# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# ---------------------------------------------------------------------------
# Job and placement
# ---------------------------------------------------------------------------

variable "job_name" {
  description = "Name of the job. Empty uses the name of the release. It also names the services (<job>: the admin port with /ping, <job>-<entrypoint>: the entrypoints)."
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

variable "datacenters" {
  description = "Datacenters of the job."
  type        = list(string)
  default     = ["*"]

  ui {
    tab   = "general"
    group = "Placement"
  }

  validation {
    min_items = 1
    item {
      min_length = 1
    }
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

  validation {
    one_of = ["service", "system"]
  }

  ui {
    tab   = "general"
    group = "Placement"
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

  validation {
    item {
      attribute "operator" {
        one_of = ["=", "!=", ">", ">=", "<", "<=", "regexp", "set_contains", "set_contains_any", "is_set", "is_not_set", "version", "semver"]
      }
    }
  }

  ui {
    tab   = "general"
    group = "Placement"
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

  validation {
    one_of = ["DEBUG", "INFO", "WARN", "ERROR"]
  }

  ui {
    tab   = "general"
    group = "Logs"
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
    tab    = "entrypoints"
    group  = "Entrypoints"
    widget = "object-list"
  }

  validation {
    min_items = 1
    item {
      attribute "protocol" {
        one_of = ["http", "https", "tcp", "udp"]
      }
    }
  }
}

variable "network_mode" {
  description = "\"host\": Traefik binds the entrypoint ports on the node itself (the client addresses stay visible, UDP works); \"bridge\": the ports are mapped into the allocation's network namespace."
  type        = string
  default     = "host"

  validation {
    one_of = ["host", "bridge"]
  }

  ui {
    tab   = "entrypoints"
    group = "Network"
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
    item {
      pattern = "^[a-zA-Z0-9_~/-]+$"
    }
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

  validation {
    one_of = ["VersionTLS12", "VersionTLS13"]
  }

  ui {
    tab   = "tls"
    group = "Options"
  }
}

# ---------------------------------------------------------------------------
# Routing: the native catalog and static file configuration
# ---------------------------------------------------------------------------

variable "mtls" {
  description = "Give Traefik a workload certificate of native mTLS: the admin service gets an mtls block (app mode), and Traefik presents the certificate to the backends of mtls_backends. The source of the service intentions that allow it is the service named after the job (job_name). Turning it on or off replaces the allocations."
  type        = bool
  default     = false

  ui {
    tab   = "tls"
    group = "mTLS to the backends"
  }
}

variable "mtls_backends" {
  description = "Backends Traefik reaches over native mTLS (needs mtls): one servers transport mtls-<name> each, with Traefik's workload certificate, the trust bundle and the DNS name <service>.service.<namespace>.norca that the backend's certificate carries. A route uses it with the tags traefik.http.services.<svc>.loadbalancer.server.scheme=https and traefik.http.services.<svc>.loadbalancer.serversTransport=mtls-<name>@file. namespace: the backend's, the job's namespace (or default) when empty. Names: letters, digits, - and _."
  type = list(object({
    name      = string
    service   = string
    namespace = optional(string, "")
  }))
  default = []

  ui {
    tab    = "tls"
    group  = "mTLS to the backends"
    widget = "object-list"
  }
}

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
  description = "Namespaces whose services Traefik routes to. Other namespaces than the job's need the ACL policy that the notes of the module print."
  type        = list(string)
  default     = ["default"]

  ui {
    tab     = "routing"
    group   = "Catalog"
    show_if = "catalog_enabled"
  }

  validation {
    min_items = 1
    item {
      min_length = 1
    }
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

variable "acme_challenge" {
  description = "Leave the path of the ACME HTTP-01 challenge (/.well-known/acme-challenge/) out of the redirect of the http entrypoints with redirect_to, so that the service that answers it (the norca-acme module) can route it by its catalog tags. The redirect is then a router of the dynamic configuration with a priority above every other router, instead of the redirection of the entrypoint. Needs the catalog (catalog_enabled) with the namespace of that service."
  type        = bool
  default     = false

  ui {
    tab   = "entrypoints"
    group = "Entrypoints"
  }
}

variable "dynamic_config" {
  description = "Static routes in Traefik's dynamic configuration (YAML of the file provider): routers, services and middlewares to fixed backends, for HTTP, WebSocket, gRPC (h2c://), TCP and UDP. Applied without a restart. See the examples of the module."
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

rule "acme_challenge" {
  condition     = !var.acme_challenge || var.catalog_enabled
  error_message = "acme_challenge needs catalog_enabled: the service that answers the challenge is routed by its catalog tags."
}

rule "mtls_backends_need_mtls" {
  condition     = length(var.mtls_backends) == 0 || var.mtls
  error_message = "mtls_backends needs mtls = true."
}

rule "mtls_backend_names" {
  condition     = alltrue([for b in var.mtls_backends : can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,57}$", b.name))])
  error_message = "the name of an mtls backend: letters, digits, - and _, at most 58 characters."
}

rule "mtls_backends_unique" {
  condition     = length(distinct([for b in var.mtls_backends : b.name])) == length(var.mtls_backends)
  error_message = "an mtls backend is defined twice."
}

rule "mtls_backend_service" {
  condition     = alltrue([for b in var.mtls_backends : b.service != ""])
  error_message = "an mtls backend needs a service."
}

rule "entrypoint_names" {
  condition     = alltrue([for e in var.entrypoints : can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,30}$", e.name)) && e.name != "traefik"])
  error_message = "the name of an entrypoint: letters, digits, - and _, at most 31 characters; \"traefik\" is the admin entrypoint (admin_port)."
}

rule "entrypoints_unique" {
  condition     = length(distinct([for e in var.entrypoints : e.name])) == length(var.entrypoints)
  error_message = "an entrypoint is defined twice."
}

# Norca reserves a static port for TCP and UDP alike.
rule "entrypoint_ports" {
  condition = (
    alltrue([for e in var.entrypoints : e.port >= 1 && e.port <= 65535 && e.port != var.admin_port]) &&
    length(distinct([for e in var.entrypoints : e.port])) == length(var.entrypoints)
  )
  error_message = "the port of an entrypoint is 1-65535, used once, and not the admin_port."
}

rule "redirects" {
  condition = alltrue([for e in var.entrypoints : e.redirect_to == "" || (
    e.protocol == "http" && contains([for t in var.entrypoints : t.name if t.protocol == "https"], e.redirect_to)
  )])
  error_message = "redirect_to is for http entrypoints, and names an https entrypoint."
}
