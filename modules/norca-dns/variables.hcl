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

variable "datacenters" {
  description = "Datacenters of the operator job. Name at least two, or a pattern, so the operator is placed again when its node or datacenter is lost."
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

variable "count" {
  description = "Instances of the operator. More than one run on different nodes with leader election: one of them writes the records, the others are standbys that take over when it is lost."
  type        = number
  default     = 1

  validation {
    integer = true
    min     = 1
    max     = 5
  }
}

variable "leader_election" {
  description = "Run the operator with leader election (-leader-election): the instances share a lease, the Variable controller-lease/norca-dns in the namespace of the job, and only the one that holds it writes the zones. Always on with more than one instance (count). Turn it on for one instance too where an allocation that was lost but still runs must not write beside its replacement (review finding CON-6e). The ACL policy of the module then grants the lease."
  type        = bool
  default     = false
}

variable "driver" {
  description = "Task driver of the operator: exec or raw_exec (the binary installed on the nodes, in the chroot of exec below /usr; raw_exec only with allow_raw_exec_nodes), docker (an image with the binary), or mock_driver (tests on dev agents only)."
  type        = string
  default     = "exec"

  validation {
    one_of = ["raw_exec", "exec", "docker", "mock_driver"]
  }

}

variable "allow_raw_exec_nodes" {
  description = "Let the job run on nodes where the raw_exec driver is enabled, and with driver = raw_exec. Off by default (review finding JOG-19): a raw_exec task, or alloc-node-exec, on such a node runs as the user of the agent and reads the secrets directory of every allocation of the node, so the workload identity token of this job and the ACL policies bound to it. Without it the job keeps off nodes whose attribute driver.raw_exec is set, and the module refuses driver = raw_exec (the rule raw_exec). Turn it on only where every token that may place raw_exec work or use alloc-node-exec on those nodes may hold the policies of the operator anyway (a lab, a single-tenant cluster)."
  type        = bool
  default     = false
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

  validation {
    one_of = ["debug", "info", "warn", "error"]
  }

}

# ---------------------------------------------------------------------------
# The operator
# ---------------------------------------------------------------------------

variable "requeue" {
  description = "Time after which a record is compared with its zone again: a change made in the zone by hand is set back then at the latest. More than zero."
  type        = string
  default     = "5m"

  validation {
    pattern = "^0*[1-9][0-9]*(s|m|h)$"
  }
}

variable "zone_token_namespace" {
  description = "Namespace of the Variables holding the tokens of the DNS zones (the token_variable of a provider of norca-provider). Empty: the namespace of the operator job."
  type        = string
  default     = ""

  validation {
    pattern = "^([a-zA-Z0-9-]{1,128})?$"
  }
}

variable "zone_token_path" {
  description = "Path pattern of the token Variables of the DNS zones the operator may read."
  type        = string
  default     = "providers/*"
}

variable "zone_ttl" {
  description = "How old the heartbeat of a DNS zone may be. More than zero."
  type        = string
  default     = "3m"

  validation {
    pattern = "^0*[1-9][0-9]*(s|m|h)$"
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
  description = "Register the norca.io/DNSRecord object kind. Disable it if another release of this module registers the kind."
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

rule "raw_exec" {
  condition     = var.driver != "raw_exec" || var.allow_raw_exec_nodes
  error_message = "driver = \"raw_exec\" needs allow_raw_exec_nodes = true, as the job would then run on a node with the raw_exec driver, where a raw_exec task or alloc-node-exec reads its identity token (review finding JOG-19). Use driver = \"exec\" or \"docker\", or set allow_raw_exec_nodes = true knowingly."
}
