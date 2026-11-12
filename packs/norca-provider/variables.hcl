# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# ---------------------------------------------------------------------------
# Provider job
# ---------------------------------------------------------------------------

variable "job_name" {
  description = "Name of the provider job. The ACL policy of the provider is bound to it, and its Variable (nomad/jobs/<job_name>) holds the secrets of the providers."
  type        = string
  default     = "norca-provider"

  validation {
    pattern = "^[a-zA-Z0-9][a-zA-Z0-9_-]{0,62}$"
  }
}

variable "namespace" {
  description = "Namespace of the provider job."
  type        = string
  default     = "default"

  validation {
    min_length = 1
  }
}

variable "region" {
  description = "Region of the provider job. Empty leaves it to the region of the release."
  type        = string
  default     = ""
}

variable "datacenters" {
  description = "Datacenters of the provider job. The provider is one instance: what makes it survive the loss of a datacenter is being placed again in another, so name at least two, or a pattern."
  type        = list(string)
  default     = ["*"]

  validation {
    min_items       = 1
    item_min_length = 1
  }
}

variable "allow_single_datacenter" {
  description = "Accept a single named datacenter for the provider job. Without it the pack refuses to render: a provider bound to one datacenter is lost with it, and no node or load balancer is made until the datacenter is back."
  type        = bool
  default     = false
}

variable "node_pool" {
  description = "Node pool of the provider job. Whatever the pool, it never runs on a node the node scaling operator created (meta norca.instance): such a node can be removed under it."
  type        = string
  default     = "default"

  validation {
    min_length = 1
  }
}

variable "driver" {
  description = "Task driver of the provider: raw_exec or exec (the binary installed on the nodes), docker (an image with the binary), or mock_driver (tests on dev agents only). The docker platform of norca-provider needs the docker CLI of its host: raw_exec."
  type        = string
  default     = "raw_exec"

  ui {
    options = ["raw_exec", "exec", "docker", "mock_driver"]
  }
}

variable "binary" {
  description = "Path of the norca-provider binary on the nodes (raw_exec, exec). Build it in a norca-platform checkout with: go build -o norca-provider ./cmd/norca-provider"
  type        = string
  default     = "/usr/local/bin/norca-provider"
}

variable "image" {
  description = "Container image with the norca-provider binary as its entrypoint (docker; the Dockerfile of norca-platform builds one)."
  type        = string
  default     = ""
}

variable "cpu" {
  description = "CPU of the provider, in MHz."
  type        = number
  default     = 100

  validation {
    integer = true
    min     = 20
  }
}

variable "memory" {
  description = "Memory of the provider, in MB."
  type        = number
  default     = 64

  validation {
    integer = true
    min     = 16
  }
}

variable "log_level" {
  description = "Log level of the provider."
  type        = string
  default     = "info"

  ui {
    options = ["debug", "info", "warn", "error"]
  }
}

# ---------------------------------------------------------------------------
# Configuration of norca-provider
# ---------------------------------------------------------------------------

variable "port" {
  description = "Static port of the provider's server: the operators call it there, so the firewall of the node must let them in."
  type        = number
  default     = 8443

  validation {
    integer = true
    min     = 1
    max     = 65535
  }
}

variable "advertise_url" {
  description = "Base URL the operators reach the provider on (advertise_url of the configuration). Empty: http(s)://<address of the task>:<port>. $${NAME} refers to the environment of the task, for example $${NORCA_IP_api}."
  type        = string
  default     = ""

  validation {
    pattern = "^(https?://[^/?#]+(/[^?#]*)?)?$"
  }
}

variable "heartbeat_interval" {
  description = "How often the status (the heartbeat) of the registrations is updated; well below the provider TTL of the operators (three minutes by default)."
  type        = string
  default     = "30s"

  validation {
    pattern = "^[0-9]+(ms|s|m|h)$"
  }
}

variable "providers" {
  description = "The providers to serve: the JSON array of the providers of the configuration of norca-provider (name, type, params, token or token_file or no_auth, token_variable, node, loadbalancer). Secrets are written as env:NAME, with NAME an item of the job's Variable (secrets = true). $${NAME} refers to the environment of the task. The default serves a mock class without a token, for trials only."
  type        = string
  default     = "[{\"name\": \"mock\", \"type\": \"mock\", \"no_auth\": true, \"loadbalancer\": {\"classes\": [{\"class\": \"mock\"}]}}]"

  validation {
    pattern = "^\\s*\\[[\\s\\S]*\\]\\s*$"
  }
}

variable "secrets" {
  description = "Give the items of the job's Variable (nomad/jobs/<job_name>) to the task as environment variables, for env:NAME in providers: the tokens of the providers and the credentials of the platforms. The Variable must exist; the task waits for it."
  type        = bool
  default     = false
}

variable "tls_enabled" {
  description = "Serve https with the certificate and key of the job's Variable (items tls_cert and tls_key). The LoadBalancer operator calls http endpoints only with -class-allow-http."
  type        = bool
  default     = false
}

variable "deregister_on_exit" {
  description = "Remove the registrations when the provider stops, so the operators report an unknown provider at once instead of waiting for the heartbeat to expire."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Admission
# ---------------------------------------------------------------------------

variable "acl_policy_enabled" {
  description = "Install the ACL policy of the provider, bound to its job. Disable it on agents without ACLs (dev agents), where policies can't be written."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------

rule "image" {
  condition     = var.driver != "docker" || var.image != ""
  error_message = "image is required when driver is docker."
}
