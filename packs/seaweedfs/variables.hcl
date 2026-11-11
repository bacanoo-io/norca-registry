# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# ---------------------------------------------------------------------------
# Job and placement
# ---------------------------------------------------------------------------

variable "job_name" {
  description = "Name of the job. Empty uses the pack name (\"seaweedfs\"). The services in the native catalog are <job>-master, <job>-volume and <job>-filer."
  type        = string
  default     = ""

  validation {
    pattern = "^([a-zA-Z0-9][a-zA-Z0-9_-]{0,50})?$"
  }
}

variable "namespace" {
  description = "Namespace of the job. Empty leaves it to the namespace of the release. The seaweedfs-csi pack finds the filer through the catalog of this namespace."
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

  validation {
    min_items       = 1
    item_min_length = 1
  }
}

variable "node_pool" {
  description = "Node pool of the job. Empty uses the default node pool."
  type        = string
  default     = ""
}

variable "node" {
  description = "Name of the node that keeps the data (node.unique.name). The data stays in data_dir of that node, so pin the server to one node; empty lets the scheduler choose, which is only right for a test."
  type        = string
  default     = ""
}

variable "constraints" {
  description = "Extra placement constraints of the job, e.g. [{attribute = \"$${meta.storage}\", operator = \"=\", value = \"true\"}]."
  type = list(object({
    attribute = string
    operator  = string
    value     = string
  }))
  default = []
}

# ---------------------------------------------------------------------------
# The weed binary
# ---------------------------------------------------------------------------

variable "artifact_url" {
  description = "URL of the SeaweedFS release archive with the weed binary, unpacked into the task directory. Empty uses binary as it is on the node."
  type        = string
  default     = "https://github.com/seaweedfs/seaweedfs/releases/download/4.51/linux_amd64.tar.gz"
}

variable "artifact_checksum" {
  description = "Checksum of the archive (type:value, as the artifact block takes it). The default is the md5 the release publishes for linux_amd64.tar.gz of 4.51."
  type        = string
  default     = "md5:49f602d0d93ccf3e13607b3ccee8ffd6"
}

variable "binary" {
  description = "Path of weed: relative to the task directory when downloaded with artifact_url (local/weed), absolute on the node otherwise."
  type        = string
  default     = "local/weed"

  validation {
    min_length = 1
  }
}

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

variable "data_dir" {
  description = "Directory of the node for the data of the master, the volume server and the filer (raw_exec runs on the host file system). Created when missing."
  type        = string
  default     = "/var/lib/seaweedfs"

  validation {
    pattern = "^/.+"
  }
}

variable "master_port" {
  description = "HTTP port of the master; its gRPC port is this + 10000."
  type        = number
  default     = 9333
}

variable "volume_port" {
  description = "HTTP port of the volume server; its gRPC port is this + 10000."
  type        = number
  default     = 8080
}

variable "filer_port" {
  description = "HTTP port of the filer; its gRPC port is this + 10000. The CSI driver uses both."
  type        = number
  default     = 8888
}

variable "replication" {
  description = "Default replication of the master (-master.defaultReplication). A single server can only keep one copy: \"000\"."
  type        = string
  default     = "000"

  validation {
    pattern = "^[0-9]{3}$"
  }
}

variable "volume_size_limit_mb" {
  description = "Size of a SeaweedFS volume file in MB (-master.volumeSizeLimitMB)."
  type        = number
  default     = 1024
}

variable "volume_max" {
  description = "Number of volume files the volume server may create (-volume.max); 0 lets SeaweedFS decide from the free disk space."
  type        = number
  default     = 0
}

variable "extra_args" {
  description = "Extra arguments of weed server, e.g. [\"-volume.index=leveldb\"]."
  type        = list(string)
  default     = []
}

variable "resources" {
  description = "CPU (MHz) and memory (MB) of the server."
  type = object({
    cpu    = number
    memory = number
  })
  default = {
    cpu    = 500
    memory = 512
  }
}
