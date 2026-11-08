# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# ---------------------------------------------------------------------------
# Operator job
# ---------------------------------------------------------------------------

variable "job_name" {
  description = "Name of the operator job. The ACL policy of the operator is bound to it."
  type        = string
  default     = "nodescaler"

  validation {
    pattern = "^[a-zA-Z0-9][a-zA-Z0-9_-]{0,62}$"
  }
}

variable "namespace" {
  description = "Namespace of the operator job and of its leader election lease."
  type        = string
  default     = "default"

  validation {
    min_length = 1
  }
}

variable "region" {
  description = "Region of the operator job. Empty leaves it to the region of the release; the operator runs once per region and scales the node groups of its region."
  type        = string
  default     = ""
}

variable "datacenters" {
  description = "Datacenters of the operator job."
  type        = list(string)
  default     = ["*"]

  validation {
    min_items       = 1
    item_min_length = 1
  }
}

variable "node_pool" {
  description = "Node pool of the operator job. Run it outside the pools it scales: a scaled node can be removed under it. Whatever the pool, it never runs on a node the operator created (meta norca.instance)."
  type        = string
  default     = "default"

  validation {
    min_length = 1
  }
}

variable "count" {
  description = "Instances of the operator, on different nodes. Leader election makes one of them reconcile while the others keep a warm cache."
  type        = number
  default     = 2

  validation {
    integer = true
    min     = 1
    max     = 5
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
  description = "Path of the norca-nodescaler binary on the nodes (raw_exec, exec). Build it in a norca-platform checkout with: go build -o norca-nodescaler ./cmd/norca-nodescaler"
  type        = string
  default     = "/usr/local/bin/norca-nodescaler"
}

variable "image" {
  description = "Container image with the norca-nodescaler binary as its entrypoint (docker)."
  type        = string
  default     = ""
}

variable "cpu" {
  description = "CPU of an operator instance, in MHz."
  type        = number
  default     = 100

  validation {
    integer = true
    min     = 20
  }
}

variable "memory" {
  description = "Memory of an operator instance, in MB."
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
# Node scaling
# ---------------------------------------------------------------------------

variable "variables_namespace" {
  description = "Namespace of the Variables the operator reads: the bootstrap (nodescaler/bootstrap/<region>, with the key of the node CA) and the network ranges (nodescaler/network/<region>) the deployer writes, and the tokens of the providers (keep them under nodescaler/)."
  type        = string
  default     = "default"

  validation {
    min_length = 1
  }
}

variable "provider_ttl" {
  description = "How old the heartbeat of a NodeProvider may be before the provider counts as unavailable."
  type        = string
  default     = "3m"

  validation {
    pattern = "^[0-9]+(s|m|h)$"
  }
}

variable "provider_allow_http" {
  description = "Accept http endpoints of providers. For development and labs only: the token of a provider travels in the clear."
  type        = bool
  default     = false
}

variable "resync" {
  description = "Period of the full resynchronization of the node groups: how soon a change of the nodes or of the provider is seen without a change of the object."
  type        = string
  default     = "5m"

  validation {
    pattern = "^[0-9]+(s|m|h)$"
  }
}

variable "orphan_after" {
  description = "Age after which an instance of a node group that is gone, and that has no node, is deleted."
  type        = string
  default     = "15m"

  validation {
    pattern = "^[0-9]+(s|m|h)$"
  }
}

variable "orphan_sweep" {
  description = "How often the leader looks for orphaned instances at the providers."
  type        = string
  default     = "5m"

  validation {
    pattern = "^[0-9]+(s|m|h)$"
  }
}

variable "delete_orphans" {
  description = "Delete the instances of a node group that is gone that run a node too. Without it they are only reported (an OrphanedInstance event of their NodeProvider): they run work."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Join: the nodes make their own keys
# ---------------------------------------------------------------------------

variable "join_enabled" {
  description = "Serve the join endpoint: the bootstrap of a new node carries a one-time token instead of its key and certificate, and norca-join on the machine makes the key, fetches the certificate and renews it (the node then has no age limit). The machines need norca-join (the item join_binary of the bootstrap)."
  type        = bool
  default     = false
}

variable "join_port" {
  description = "Static port of the join endpoint on the nodes of the operator. The nodes the operator creates must reach it (the firewall of the cluster nodes)."
  type        = number
  default     = 8490

  validation {
    integer = true
    min     = 1
    max     = 65535
  }
}

variable "join_validity" {
  description = "Validity of the certificate of a node that renews itself; it renews at two thirds."
  type        = string
  default     = "168h"

  validation {
    pattern = "^[0-9]+(m|h)$"
  }
}

variable "join_check_address" {
  description = "The join endpoint accepts a join or a renewal only from an address the provider reports for the instance (a stolen token or key used elsewhere is refused). Turn it off where a proxy, a load balancer or NAT in front of the endpoint changes the source address, such as join_urls behind a load balancer that does not keep it."
  type        = bool
  default     = true
}

variable "join_key_store" {
  description = "Where the nodes that join keep their keys, unless their NodeGroup sets spec.join.key_store: file (a key file), tpm (made in the TPM 2.0 of the machine and never leaving it; a machine without /dev/tpmrm0 does not join; Linux) or auto (the TPM where the machine has one, else a file)."
  type        = string
  default     = "file"

  validation {
    pattern = "^(file|tpm|auto)$"
  }
}

variable "join_urls" {
  description = "Stable https URLs of the join endpoint (a DNS name or a load balancer in front of the operator instances). Empty: the instances of the service <job_name>-join of the native catalog, which move with the operator."
  type        = list(string)
  default     = []

  validation {
    item_pattern = "^https://[^ ]+$"
  }
}
