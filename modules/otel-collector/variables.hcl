# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# ---------------------------------------------------------------------------
# Job and placement
# ---------------------------------------------------------------------------

variable "job_name" {
  description = "Name of the system job. Empty uses the name of the release. It also names the services (<job>: health, <job>-otlp-grpc, <job>-otlp-http)."
  type        = string
  default     = ""

  validation {
    pattern = "^([a-zA-Z0-9][a-zA-Z0-9_-]{0,52})?$"
  }
}

variable "datacenters" {
  description = "Datacenters of the job."
  type        = list(string)
  default     = ["*"]

  validation {
    min_items = 1
    item {
      min_length = 1
    }
  }
}

variable "node_pool" {
  description = "Node pool of the job: a collector runs on every node of it. Empty uses the default node pool; \"all\" covers every node pool."
  type        = string
  default     = ""
}

variable "constraints" {
  description = "Extra placement constraints, e.g. [{attribute = \"$${meta.monitoring}\", operator = \"!=\", value = \"off\"}]."
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
  description = "Image of the collector (docker driver): the contrib distribution of the OpenTelemetry Collector (Apache-2.0), which has every receiver the module uses."
  type        = string
  default     = "docker.io/otel/opentelemetry-collector-contrib:0.162.0"

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

variable "resources" {
  description = "Resources of a collector: cpu in MHz, memory in MB. The memory_limiter processor keeps the collector at 80% of the memory."
  type = object({
    cpu    = number
    memory = number
  })
  default = {
    cpu    = 200
    memory = 256
  }
}

variable "collection_interval" {
  description = "Interval of the host metrics, the scrapes and the PostgreSQL statistics."
  type        = string
  default     = "30s"

  validation {
    pattern = "^[0-9]+(s|m)$"
  }
}

variable "log_level" {
  description = "Log level of the collector itself (service.telemetry.logs.level): debug, info, warn, error."
  type        = string
  default     = "info"

  validation {
    one_of = ["debug", "info", "warn", "error"]
  }

}

# ---------------------------------------------------------------------------
# OTLP receiver for the applications on the node
# ---------------------------------------------------------------------------

variable "otlp_enabled" {
  description = "Receive OTLP (traces, metrics, logs) from the applications of the node and forward it to OpenObserve: gRPC on otlp_grpc_port, HTTP on otlp_http_port, on the node address."
  type        = bool
  default     = true
}

variable "otlp_grpc_port" {
  description = "Static OTLP/gRPC port on every node."
  type        = number
  default     = 4317

  validation {
    integer = true
    min     = 1
    max     = 65535
  }
}

variable "otlp_http_port" {
  description = "Static OTLP/HTTP port on every node."
  type        = number
  default     = 4318

  validation {
    integer = true
    min     = 1
    max     = 65535
  }
}

variable "host_network" {
  description = "Client host_network the OTLP ports bind to (e.g. the private network). Empty uses the default address of the node."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Export to OpenObserve
# ---------------------------------------------------------------------------

variable "openobserve_service" {
  description = "HTTP service of OpenObserve in the native catalog, in the namespace of the job (the openobserve module registers \"openobserve\": the instance or the routers). The first instance is the endpoint. Ignored when openobserve_endpoint is set."
  type        = string
  default     = "openobserve"

  validation {
    pattern = "^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$"
  }
}

variable "openobserve_endpoint" {
  description = "Base URL of OpenObserve (e.g. https://observe.example.com:5080) instead of the catalog lookup."
  type        = string
  default     = ""

  validation {
    pattern = "^(https?://[^/?#]+)?$"
  }
}

variable "openobserve_tls" {
  description = "TLS to OpenObserve: \"mtls\" (default: the collector gets its own workload identity, mtls { mode = \"app\" } on its health service, and trusts the trust bundle of the region; the name checked is openobserve_server_name), \"secret\" (the CA of openobserve_ca_secret_path), \"system\" (the system CAs) or \"none\" (plain HTTP)."
  type        = string
  default     = "mtls"

  validation {
    one_of = ["mtls", "secret", "system", "none"]
  }

}

variable "openobserve_server_name" {
  description = "Name the certificate of OpenObserve must carry. Empty: <openobserve_service>.service.<namespace>.norca, the name of Norca's workload certificate."
  type        = string
  default     = ""

  validation {
    pattern = "^([a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?)?$"
  }
}

variable "openobserve_ca_secret_path" {
  description = "openobserve_tls = \"secret\": secret with the PEM CA (item ca)."
  type        = string
  default     = ""
}

variable "openobserve_organization" {
  description = "Organization the collector writes into. Empty uses the item organization of the ingest secret."
  type        = string
  default     = ""

  validation {
    pattern = "^([A-Za-z0-9_-]{1,64})?$"
  }
}

variable "ingest_secret_path" {
  description = "Secret with the ingest credentials (items username, password, organization), written by the bootstrap task of the openobserve module."
  type        = string
  default     = "openobserve/ingest"

  validation {
    min_length = 1
  }
}

# ---------------------------------------------------------------------------
# Metrics sources
# ---------------------------------------------------------------------------

variable "hostmetrics_enabled" {
  description = "Host metrics of the node (host_metrics receiver: cpu, memory, load, disk, filesystem, network, paging), read from the host's /proc and / mounted read-only at /hostfs."
  type        = bool
  default     = true
}

variable "host_root_volume" {
  description = "Client host volume of the host's root directory, read-only (client { host_volume \"hostfs\" { path = \"/\", read_only = true } }), mounted at /hostfs. Empty: no mount, the host metrics then describe the container (filesystems) except cpu, memory and load."
  type        = string
  default     = "hostfs"
}

variable "nomad_metrics_enabled" {
  description = "Scrape the metrics of the Norca agent of the node (/v1/metrics?format=prometheus; needs telemetry { prometheus { enabled = true } } in the agent configuration). Ignored when nomad_otlp_enabled is set."
  type        = bool
  default     = true
}

variable "nomad_otlp_enabled" {
  description = "OTLP mode: the Norca agent of the node pushes its telemetry over OTLP/gRPC, in plain text, to a receiver of the collector on 127.0.0.1:nomad_otlp_port (telemetry { otlp {} } in the agent configuration), and the Prometheus scrape of the agent is off."
  type        = bool
  default     = false
}

variable "nomad_otlp_port" {
  description = "Port of the OTLP/gRPC receiver for the agent on 127.0.0.1 (nomad_otlp_enabled). 4317 is the agent's default endpoint, 127.0.0.1:4317."
  type        = number
  default     = 4317

  validation {
    integer = true
    min     = 1
    max     = 65535
  }
}

variable "nomad_address" {
  description = "Address of the local Norca agent as the collector (host networking) reaches it: the metrics and the catalog for the discovery of the other sources. https:// when the agent has tls { http = true }."
  type        = string
  default     = "http://127.0.0.1:4646"

  validation {
    pattern = "^https?://[^/?#]+$"
  }
}

variable "nomad_ca_secret_path" {
  description = "Secret with the CA of the agent's HTTPS certificate (item ca; e.g. norca-agent-ca.pem). Empty uses the system CAs. The certificates of norca tls cert create carry 127.0.0.1 and localhost."
  type        = string
  default     = ""
}

variable "discovery_namespaces" {
  description = "Namespaces the collector looks for metrics services in (nomad_sd_configs of the Prometheus receiver, one per namespace, with the collector's workload identity). Only the instances on the collector's own node are scraped."
  type        = list(string)
  default     = ["default"]

  validation {
    unique = true
    item {
      pattern = "^[a-zA-Z0-9-]{1,128}$"
    }
  }
}

variable "nats_metrics_enabled" {
  description = "Scrape the NATS exporters of the nats module (metrics_enabled there) on the node: service nats_metrics_service."
  type        = bool
  default     = true
}

variable "nats_metrics_service" {
  description = "Service of the NATS exporters (<job>-metrics of the nats module)."
  type        = string
  default     = "nats-metrics"

  validation {
    pattern = "^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$"
  }
}

variable "forgejo_metrics_enabled" {
  description = "Scrape /metrics of Forgejo (metrics_enabled of the forgejo module: its HTTP service carries the tag metrics) on the node, with the bearer token of forgejo_metrics_secret_path."
  type        = bool
  default     = true
}

variable "forgejo_service" {
  description = "HTTP service of Forgejo; instances with the tag https are scraped over HTTPS."
  type        = string
  default     = "forgejo"

  validation {
    pattern = "^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$"
  }
}

variable "forgejo_metrics_secret_path" {
  description = "Secret with the bearer token of Forgejo's /metrics (item token; the same secret as in the forgejo module). Optional: without it no token is sent."
  type        = string
  default     = "forgejo/metrics"

  validation {
    min_length = 1
  }
}

variable "forgejo_tls_server_name" {
  description = "Name the certificate of Forgejo carries (HTTPS instances are scraped by address): domain of the forgejo module."
  type        = string
  default     = "forgejo.internal"

  validation {
    pattern = "^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$"
  }
}

variable "mtls_gateway_metrics_enabled" {
  description = "Scrape the Envoy statistics of the mTLS gateways (metrics_enabled of the mtls-gateway module) on the node: service mtls_gateway_metrics_service."
  type        = bool
  default     = true
}

variable "mtls_gateway_metrics_service" {
  description = "Service of the gateway statistics (<service_name>-metrics of the mtls-gateway module)."
  type        = string
  default     = "mtls-gateway-metrics"

  validation {
    pattern = "^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$"
  }
}

variable "consul_metrics_enabled" {
  description = "Scrape the Consul agent of the node (metrics_enabled of the consul module registers its HTTP port as consul_metrics_service) on 127.0.0.1, with the token of consul_metrics_secret_path."
  type        = bool
  default     = true
}

variable "consul_metrics_service" {
  description = "Service of the Consul agents' HTTP ports (<job>-metrics of the consul module)."
  type        = string
  default     = "consul-metrics"

  validation {
    pattern = "^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$"
  }
}

variable "consul_metrics_secret_path" {
  description = "Secret with the Consul ACL token of the metrics (item token; the same secret as metrics_token_secret_path of the consul module). Optional."
  type        = string
  default     = "consul/metrics"

  validation {
    min_length = 1
  }
}

variable "postgres_metrics_enabled" {
  description = "PostgreSQL statistics with the postgresql receiver for the instances of postgres_service on the node (the postgres module, in the namespace of this job), as the monitoring role of postgres_secret_path."
  type        = bool
  default     = true
}

variable "postgres_service" {
  description = "Service of PostgreSQL in the native catalog, in the namespace of the job (nomadService only sees the job's namespace)."
  type        = string
  default     = "postgres"

  validation {
    pattern = "^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$"
  }
}

variable "postgres_user" {
  description = "Monitoring role (monitoring_user of the postgres module, with pg_monitor)."
  type        = string
  default     = "monitoring"

  validation {
    pattern = "^[a-z_][a-z0-9_]{0,62}$"
  }
}

variable "postgres_secret_path" {
  description = "Secret with the password of the monitoring role (item password; monitoring_secret_path of the postgres module). Optional."
  type        = string
  default     = "postgres/monitoring"

  validation {
    min_length = 1
  }
}

variable "postgres_tls" {
  description = "TLS of the PostgreSQL connections, matching tls_mode of the postgres module: \"none\" (plain; the receiver's own default would require TLS), \"require\" (encrypted, not verified) or \"verify-ca\" (encrypted, the server certificate checked against the trust bundle of the region; for tls_mode = \"mtls\" of the postgres module, needs openobserve_tls = \"mtls\")."
  type        = string
  default     = "none"

  validation {
    one_of = ["none", "require", "verify-ca"]
  }

}

variable "self_metrics_enabled" {
  description = "Scrape the collector's own metrics (on 127.0.0.1 and a dynamic port)."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Rules: conditions on the items of lists and maps and across variables,
# checked before rendering by rigger and by the servers that render the module.
# ---------------------------------------------------------------------------

rule "constraints" {
  condition     = alltrue([for x in var.constraints : x.attribute != null && x.operator != ""])
  error_message = "constraints: each item needs attribute and operator; operator must not be empty."
}

rule "resources" {
  condition = (
    floor(var.resources.cpu) == var.resources.cpu &&
    var.resources.cpu >= 50 &&
    floor(var.resources.memory) == var.resources.memory &&
    var.resources.memory >= 128
  )
  error_message = "resources: needs cpu and memory; cpu must be at least 50; memory must be at least 128."
}

rule "openobserve_ca_secret_path" {
  condition     = var.openobserve_tls != "secret" || var.openobserve_ca_secret_path != ""
  error_message = "openobserve_ca_secret_path is required when openobserve_tls is secret."
}

rule "otlp_ports" {
  condition     = !var.otlp_enabled || var.otlp_grpc_port != var.otlp_http_port
  error_message = "otlp_grpc_port must differ from otlp_http_port."
}

rule "openobserve_ca" {
  condition     = var.openobserve_tls != "secret" || var.openobserve_ca_secret_path != ""
  error_message = "openobserve_tls = \"secret\" needs openobserve_ca_secret_path."
}

rule "something_to_collect" {
  condition     = var.otlp_enabled || var.hostmetrics_enabled || var.self_metrics_enabled || var.nomad_metrics_enabled || var.nomad_otlp_enabled
  error_message = "enable at least one of otlp_enabled, hostmetrics_enabled, self_metrics_enabled, nomad_metrics_enabled, nomad_otlp_enabled."
}
