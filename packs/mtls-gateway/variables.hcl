# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# ---------------------------------------------------------------------------
# Job and placement
# ---------------------------------------------------------------------------

variable "job_name" {
  description = "Name of the gateway job. The job always runs in the default namespace: upstreams of other regions look for gateways only there."
  type        = string
  default     = "mtls-gateway"
}

variable "region" {
  description = "Region of the gateway job. Empty leaves it to the region of the release (norca pack run --region, or --regions for several regions at once)."
  type        = string
  default     = ""
}

variable "datacenters" {
  description = "Datacenters of the gateway job."
  type        = list(string)
  default     = ["*"]
}

variable "node_pool" {
  description = "Node pool of the gateway job. Empty uses the default node pool."
  type        = string
  default     = ""
}

variable "job_type" {
  description = "system (default): one gateway on every eligible node of the region. service: count gateways on distinct nodes, for regions where only some nodes are reachable from the other regions."
  type        = string
  default     = "system"
}

variable "count" {
  description = "Number of gateway instances with job_type = \"service\". Ignored for system jobs."
  type        = number
  default     = 2
}

variable "distinct_hosts" {
  description = "With job_type = \"service\": place the gateway instances on different nodes (they use the same static port)."
  type        = bool
  default     = true
}

variable "constraints" {
  description = "Extra placement constraints of the job, e.g. [{attribute = \"$${meta.vpn}\", operator = \"=\", value = \"true\"}] for the nodes on the VPN between the regions."
  type = list(object({
    attribute = string
    operator  = string
    value     = string
  }))
  default = []
}

variable "update_max_parallel" {
  description = "Gateways replaced at a time on updates (the other regions keep using the remaining instances)."
  type        = number
  default     = 1
}

# ---------------------------------------------------------------------------
# Service and network
# ---------------------------------------------------------------------------

variable "service_name" {
  description = "Name of the gateway service. mtls-gateway is the name upstreams with a region look for by default; other names need gateway = \"<name>\" in the upstream block."
  type        = string
  default     = "mtls-gateway"
}

variable "service_tags" {
  description = "Tags of the gateway service."
  type        = list(string)
  default     = []
}

variable "port" {
  description = "Static port of the gateway on the nodes: the nodes of the other regions connect to <node address>:<port>."
  type        = number
  default     = 8443
}

variable "host_network" {
  description = "Client host_network to bind the gateway port to (e.g. the VPN interface). Empty uses the default address of the node."
  type        = string
  default     = ""
}

variable "network_mode" {
  description = "Network mode of the group: bridge (default) or host. raw_exec Envoy tasks need host."
  type        = string
  default     = "bridge"
}

# ---------------------------------------------------------------------------
# Envoy task
# ---------------------------------------------------------------------------

variable "envoy_task_enabled" {
  description = "false (default): the servers inject the Envoy task (official image from the node meta norca.mtls.envoy_*, 100 MHz / 128 MB). true: the pack defines the task itself (kind mtls-gateway:<service>) with the envoy_* variables below; the servers then inject none."
  type        = bool
  default     = false
}

variable "envoy_driver" {
  description = "Driver of the Envoy task defined by the pack: docker, podman, exec or raw_exec (an Envoy binary on the nodes)."
  type        = string
  default     = "docker"
}

variable "envoy_image" {
  description = "Envoy image of the task defined by the pack (docker, podman), e.g. docker.io/envoyproxy/envoy:v1.40.1. Empty uses the image of the node meta (norca.mtls.envoy_image, or registry, repository, tag and digest with the client defaults)."
  type        = string
  default     = ""
}

variable "envoy_binary" {
  description = "Path of the Envoy binary on the nodes (exec, raw_exec). Norca is tested against Envoy 1.39 and 1.40."
  type        = string
  default     = "/usr/local/bin/envoy"
}

variable "envoy_log_level" {
  description = "Envoy log level of the task defined by the pack (trace, debug, info, warning, error, critical, off). Empty uses the node meta norca.mtls.envoy_log_level (default info)."
  type        = string
  default     = ""
}

variable "envoy_resources" {
  description = "Resources of the Envoy task defined by the pack: cpu in MHz, memory in MB."
  type = object({
    cpu    = number
    memory = number
  })
  default = {
    cpu    = 100
    memory = 128
  }
}

# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------

variable "metrics_enabled" {
  description = "Expose the Prometheus statistics of Envoy (/stats/prometheus only) on the port metrics, registered as <service_name>-metrics for the otel-collector pack. Needs envoy_task_enabled: the injected task has no admin interface. The admin interface listens on 127.0.0.1 only; a separate listener forwards GET /stats/prometheus to it and answers 404 for every other path."
  type        = bool
  default     = false
}

variable "metrics_port" {
  description = "Port of the metrics listener on the node; 0 (default) picks a dynamic port, which the collector finds through the catalog."
  type        = number
  default     = 0
}
