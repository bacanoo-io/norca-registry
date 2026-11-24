# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# ---------------------------------------------------------------------------
# Operator job
# ---------------------------------------------------------------------------

variable "job_name" {
  description = "Name of the operator job. The ACL policy of the operator is bound to it, and it is the name of the service that answers the HTTP-01 challenge."
  type        = string
  default     = "norca-acme"

  validation {
    pattern = "^[a-zA-Z0-9][a-zA-Z0-9_-]{0,62}$"
  }
}

variable "datacenters" {
  description = "Datacenters of the operator job. The operator is one instance: when its node or its datacenter is lost it is placed again in another, so name at least two, or a pattern."
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

  validation {
    one_of = ["raw_exec", "exec", "docker", "mock_driver"]
  }

}

variable "binary" {
  description = "Path of the norca-acme binary on the nodes (raw_exec, exec). Build it in a norca-platform checkout with: go build -o norca-acme ./cmd/norca-acme"
  type        = string
  default     = "/usr/local/bin/norca-acme"
}

variable "image" {
  description = "Container image with the norca-acme binary as its entrypoint (docker)."
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

  validation {
    one_of = ["debug", "info", "warn", "error"]
  }

}

# ---------------------------------------------------------------------------
# The operator
# ---------------------------------------------------------------------------

variable "controller" {
  description = "The name issuers name this operator by (spec.external.controller of a CertificateIssuer)."
  type        = string
  default     = "norca-acme"

  validation {
    pattern = "^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$"
  }
}

variable "interval" {
  description = "Time between two passes over the issuers and the orders."
  type        = string
  default     = "5s"

  validation {
    pattern = "^[0-9]+(ms|s|m)$"
  }
}

variable "secret_prefix" {
  description = "Path prefix of the secrets of the operator in its namespace: accounts/<issuer> (the account keys), issued/<issuer>/<serial> (the certificates it issued, until they expire, for a revocation), and what an administrator puts there, such as an external account binding. The ACL policy grants the operator this prefix only."
  type        = string
  default     = "norca-acme/"

  validation {
    pattern = "^[a-zA-Z0-9][a-zA-Z0-9._/-]*/$"
  }
}

variable "retry_base" {
  description = "Delay after the first failed attempt of an order; doubled with every further one. Certificate authorities limit the rate of orders: keep it at a minute or more."
  type        = string
  default     = "1m"

  validation {
    pattern = "^[0-9]+(s|m|h)$"
  }
}

variable "retry_max" {
  description = "Longest delay between two attempts of an order."
  type        = string
  default     = "2h"

  validation {
    pattern = "^[0-9]+(s|m|h)$"
  }
}

variable "max_attempts" {
  description = "Attempts after which an order is failed. The servers then place a new order later, with their own delay."
  type        = number
  default     = 8

  validation {
    integer = true
    min     = 1
  }
}

variable "acme_ca_cert" {
  description = "PEM bundle of the CA that signed the https certificate of the ACME directory, in addition to the system roots: for a private or test certificate authority (Pebble, step-ca). Not the roots of the certificates it issues: those are roots in the configuration of the issuer."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# HTTP-01
# ---------------------------------------------------------------------------

variable "http01_enabled" {
  description = "Answer the HTTP-01 challenge: the job serves /.well-known/acme-challenge/<token> and registers a service for it. Disable it when every name is proven with DNS-01."
  type        = bool
  default     = true
}

variable "http01_entrypoints" {
  description = "The http entrypoints of the Traefik pack the challenge is routed on (the entrypoints of port 80). The service of the job carries the router as catalog tags; the Traefik pack must have acme_challenge = true and the namespace of this job in its catalog_namespaces (with the ACL policy for that namespace its output prints). Empty: no tags, route the path by other means."
  type        = list(string)
  default     = ["web"]
}

# ---------------------------------------------------------------------------
# DNS-01
# ---------------------------------------------------------------------------

variable "zone_token_namespace" {
  description = "Namespace of the Variables holding the tokens of the DNS zones (the token_variable of the providers of norca-provider, item token). Empty: the namespace of the operator job."
  type        = string
  default     = ""

  validation {
    pattern = "^([a-zA-Z0-9-]{1,128})?$"
  }
}

variable "zone_token_path" {
  description = "Path pattern of those Variables, for the ACL policy of the operator."
  type        = string
  default     = "providers/*"

  validation {
    min_length = 1
  }
}

variable "zone_ttl" {
  description = "How old the heartbeat of a DNS zone may be before its provider counts as away."
  type        = string
  default     = "3m"

  validation {
    pattern = "^[0-9]+(s|m|h)$"
  }
}

variable "zone_allow_http" {
  description = "Accept http endpoints of DNS zones. The token of the zone then travels in the clear: for trials and a trusted network only."
  type        = bool
  default     = false
}

variable "zone_ca_cert" {
  description = "PEM bundle of the CA that signed the https certificates of the DNS providers, in addition to the system roots."
  type        = string
  default     = ""
}

variable "dns_resolver" {
  description = "Recursive resolver (host:port) the name servers of a zone are found with, before the certificate authority is told to look. Empty: the first resolver of the node."
  type        = string
  default     = ""
}

variable "dns_propagation_check" {
  description = "Wait until every name server of the zone answers a challenge record before the certificate authority is told to look. Disable it only where the name servers cannot be reached from the operator."
  type        = bool
  default     = true
}

variable "dns_propagation_timeout" {
  description = "How long a challenge record may take to appear at the name servers."
  type        = string
  default     = "5m"

  validation {
    pattern = "^[0-9]+(s|m|h)$"
  }
}

# ---------------------------------------------------------------------------
# Admission
# ---------------------------------------------------------------------------

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
