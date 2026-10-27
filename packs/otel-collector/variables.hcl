# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# ---------------------------------------------------------------------------
# Job and placement
# ---------------------------------------------------------------------------

variable "job_name" {
  description = "Name of the system job. Empty uses the pack name (\"otel-collector\"). It also names the services (<job>: health, <job>-otlp-grpc, <job>-otlp-http)."
  type        = string
  default     = ""
}

variable "namespace" {
  description = "Namespace of the job: the namespace of the openobserve pack, whose ingest secret it reads. Empty leaves it to the namespace of the release."
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
  description = "Image of the collector (docker driver): the contrib distribution of the OpenTelemetry Collector (Apache-2.0), which has every receiver the pack uses."
  type        = string
  default     = "docker.io/otel/opentelemetry-collector-contrib:0.162.0"
}

variable "image_digest" {
  description = "Digest of the image (sha256:...), appended as image@digest to pin the content. Empty uses the tag alone."
  type        = string
  default     = ""
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
}

variable "log_level" {
  description = "Log level of the collector itself (service.telemetry.logs.level): debug, info, warn, error."
  type        = string
  default     = "info"
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
}

variable "otlp_http_port" {
  description = "Static OTLP/HTTP port on every node."
  type        = number
  default     = 4318
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
  description = "HTTP service of OpenObserve in the native catalog, in the namespace of the job (the openobserve pack registers \"openobserve\": the instance or the routers). The first instance is the endpoint. Ignored when openobserve_endpoint is set."
  type        = string
  default     = "openobserve"
}

variable "openobserve_endpoint" {
  description = "Base URL of OpenObserve (e.g. https://observe.example.com:5080) instead of the catalog lookup."
  type        = string
  default     = ""
}

variable "openobserve_tls" {
  description = "TLS to OpenObserve: \"mtls\" (default: the collector gets its own workload identity, mtls { mode = \"app\" } on its health service, and trusts the trust bundle of the region; the name checked is openobserve_server_name), \"secret\" (the CA of openobserve_ca_secret_path), \"system\" (the system CAs) or \"none\" (plain HTTP)."
  type        = string
  default     = "mtls"
}

variable "openobserve_server_name" {
  description = "Name the certificate of OpenObserve must carry. Empty: <openobserve_service>.service.<namespace>.nomad, the name of Norca's workload certificate."
  type        = string
  default     = ""
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
}

variable "ingest_secret_path" {
  description = "Secret with the ingest credentials (items username, password, organization), written by the bootstrap task of the openobserve pack."
  type        = string
  default     = "openobserve/ingest"
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
  description = "Metrics of the Norca agent of the node (/v1/metrics?format=prometheus; needs telemetry { prometheus_metrics = true } in the agent configuration)."
  type        = bool
  default     = true
}

variable "nomad_address" {
  description = "Address of the local Norca agent as the collector (host networking) reaches it: the metrics and the catalog for the discovery of the other sources. https:// when the agent has tls { http = true }."
  type        = string
  default     = "http://127.0.0.1:4646"
}

variable "nomad_ca_secret_path" {
  description = "Secret with the CA of the agent's HTTPS certificate (item ca; e.g. nomad-agent-ca.pem). Empty uses the system CAs. The certificates of norca tls cert create carry 127.0.0.1 and localhost."
  type        = string
  default     = ""
}

variable "discovery_namespaces" {
  description = "Namespaces the collector looks for metrics services in (nomad_sd_configs of the Prometheus receiver, one per namespace, with the collector's workload identity). Only the instances on the collector's own node are scraped."
  type        = list(string)
  default     = ["default"]
}

variable "nats_metrics_enabled" {
  description = "Scrape the NATS exporters of the nats pack (metrics_enabled there) on the node: service nats_metrics_service."
  type        = bool
  default     = true
}

variable "nats_metrics_service" {
  description = "Service of the NATS exporters (<job>-metrics of the nats pack)."
  type        = string
  default     = "nats-metrics"
}

variable "forgejo_metrics_enabled" {
  description = "Scrape /metrics of Forgejo (metrics_enabled of the forgejo pack: its HTTP service carries the tag metrics) on the node, with the bearer token of forgejo_metrics_secret_path."
  type        = bool
  default     = true
}

variable "forgejo_service" {
  description = "HTTP service of Forgejo; instances with the tag https are scraped over HTTPS."
  type        = string
  default     = "forgejo"
}

variable "forgejo_metrics_secret_path" {
  description = "Secret with the bearer token of Forgejo's /metrics (item token; the same secret as in the forgejo pack). Optional: without it no token is sent."
  type        = string
  default     = "forgejo/metrics"
}

variable "forgejo_tls_server_name" {
  description = "Name the certificate of Forgejo carries (HTTPS instances are scraped by address): domain of the forgejo pack."
  type        = string
  default     = "forgejo.internal"
}

variable "mtls_gateway_metrics_enabled" {
  description = "Scrape the Envoy statistics of the mTLS gateways (metrics_enabled of the mtls-gateway pack) on the node: service mtls_gateway_metrics_service."
  type        = bool
  default     = true
}

variable "mtls_gateway_metrics_service" {
  description = "Service of the gateway statistics (<service_name>-metrics of the mtls-gateway pack)."
  type        = string
  default     = "mtls-gateway-metrics"
}

variable "consul_metrics_enabled" {
  description = "Scrape the Consul agent of the node (metrics_enabled of the consul pack registers its HTTP port as consul_metrics_service) on 127.0.0.1, with the token of consul_metrics_secret_path."
  type        = bool
  default     = true
}

variable "consul_metrics_service" {
  description = "Service of the Consul agents' HTTP ports (<job>-metrics of the consul pack)."
  type        = string
  default     = "consul-metrics"
}

variable "consul_metrics_secret_path" {
  description = "Secret with the Consul ACL token of the metrics (item token; the same secret as metrics_token_secret_path of the consul pack). Optional."
  type        = string
  default     = "consul/metrics"
}

variable "postgres_metrics_enabled" {
  description = "PostgreSQL statistics with the postgresql receiver for the instances of postgres_service on the node (the postgres pack, in the namespace of this job), as the monitoring role of postgres_secret_path."
  type        = bool
  default     = true
}

variable "postgres_service" {
  description = "Service of PostgreSQL in the native catalog, in the namespace of the job (nomadService only sees the job's namespace)."
  type        = string
  default     = "postgres"
}

variable "postgres_user" {
  description = "Monitoring role (monitoring_user of the postgres pack, with pg_monitor)."
  type        = string
  default     = "monitoring"
}

variable "postgres_secret_path" {
  description = "Secret with the password of the monitoring role (item password; monitoring_secret_path of the postgres pack). Optional."
  type        = string
  default     = "postgres/monitoring"
}

variable "postgres_tls" {
  description = "TLS of the PostgreSQL connections, matching tls_mode of the postgres pack: \"none\" (plain; the receiver's own default would require TLS), \"require\" (encrypted, not verified) or \"verify-ca\" (encrypted, the server certificate checked against the trust bundle of the region; for tls_mode = \"mtls\" of the postgres pack, needs openobserve_tls = \"mtls\")."
  type        = string
  default     = "none"
}

variable "self_metrics_enabled" {
  description = "Scrape the collector's own metrics (on 127.0.0.1 and a dynamic port)."
  type        = bool
  default     = true
}
