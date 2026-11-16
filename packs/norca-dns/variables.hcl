# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# ---------------------------------------------------------------------------
# Operator job
# ---------------------------------------------------------------------------

variable "job_name" {
  description = "Name of the operator job. The ACL policy of the operator is bound to it."
  type        = string
  default     = "norca-dns"

  validation {
    pattern = "^[a-zA-Z0-9][a-zA-Z0-9_-]{0,62}$"
  }
}

variable "namespace" {
  description = "Namespace of the operator job."
  type        = string
  default     = "default"

  validation {
    min_length = 1
  }
}

variable "region" {
  description = "Region of the operator job. Empty leaves it to the region of the release."
  type        = string
  default     = ""
}

variable "datacenters" {
  description = "Datacenters of the operator job. Name at least two, or a pattern, so the operator is placed again when its node or datacenter is lost."
  type        = list(string)
  default     = ["*"]

  validation {
    min_items       = 1
    item_min_length = 1
  }
}

variable "node_pool" {
  description = "Node pool of the operator job. Whatever the pool, it never runs on a node the node scaling operator created (meta norca.instance): such a node can be removed under it."
  type        = string
  default     = "default"

  validation {
    min_length = 1
  }
}

variable "driver" {
  description = "Task driver of the operator: raw_exec or exec (the binary installed on the nodes), docker (an image with the binary), or mock_driver (tests on dev agents only)."
  type        = string
  default     = "raw_exec"

  ui {
    options = ["raw_exec", "exec", "docker", "mock_driver"]
  }
}

variable "binary" {
  description = "Path of the norca-dns binary on the nodes (raw_exec, exec). Build it in a norca-platform checkout with: go build -o norca-dns ./cmd/norca-dns"
  type        = string
  default     = "/usr/local/bin/norca-dns"
}

variable "image" {
  description = "Container image with the norca-dns binary as its entrypoint (docker)."
  type        = string
  default     = ""
}

variable "cpu" {
  description = "CPU of the operator, in MHz."
  type        = number
  default     = 100

  validation {
    integer = true
    min     = 20
  }
}

variable "memory" {
  description = "Memory of the operator, in MB."
  type        = number
  default     = 64

  validation {
    integer = true
    min     = 16
  }
}

variable "log_level" {
  description = "Log level of the operator."
  type        = string
  default     = "info"

  ui {
    options = ["debug", "info", "warn", "error"]
  }
}

# ---------------------------------------------------------------------------
# The operator
# ---------------------------------------------------------------------------

variable "requeue" {
  description = "Time after which a record is compared with its zone again: a change made in the zone by hand is set back then at the latest."
  type        = string
  default     = "5m"

  validation {
    pattern = "^[0-9]+(s|m|h)$"
  }
}

variable "zone_token_namespace" {
  description = "Namespace of the Variables holding the tokens of the DNS zones (the token_variable of a provider of norca-provider)."
  type        = string
  default     = "default"
}

variable "zone_token_path" {
  description = "Path pattern of the token Variables of the DNS zones the operator may read."
  type        = string
  default     = "providers/*"
}

variable "zone_ttl" {
  description = "How old the heartbeat of a DNS zone may be."
  type        = string
  default     = "3m"

  validation {
    pattern = "^[0-9]+(s|m|h)$"
  }
}

variable "zone_allow_http" {
  description = "Accept http endpoints of DNS zones (development and labs only)."
  type        = bool
  default     = false
}

variable "zone_ca_cert" {
  description = "PEM of the CA that signed the https certificates of the DNS providers, in addition to the system roots."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Kind and admission
# ---------------------------------------------------------------------------

variable "record_kind_enabled" {
  description = "Register the norca.io/DNSRecord object kind. Disable it if another release of this pack registers the kind."
  type        = bool
  default     = true
}

variable "acl_policy_enabled" {
  description = "Install the ACL policy of the operator, bound to its job. Disable it on agents without ACLs (dev agents), where policies can't be written."
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
