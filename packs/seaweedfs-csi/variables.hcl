# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# ---------------------------------------------------------------------------
# Job and placement
# ---------------------------------------------------------------------------

variable "job_name" {
  description = "Name of the system job. Empty uses the pack name (\"seaweedfs-csi\")."
  type        = string
  default     = ""

  validation {
    pattern = "^([a-zA-Z0-9][a-zA-Z0-9_-]{0,57})?$"
  }
}

variable "namespace" {
  description = "Namespace of the job. Empty leaves it to the namespace of the release. The filer is looked up in the native catalog of this namespace (filer_service)."
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

variable "constraints" {
  description = "Extra placement constraints of the job (the nodes that get the plugin), e.g. [{attribute = \"$${meta.storage}\", operator = \"=\", value = \"true\"}]."
  type = list(object({
    attribute = string
    operator  = string
    value     = string
  }))
  default = []
}

# ---------------------------------------------------------------------------
# CSI plugin
# ---------------------------------------------------------------------------

variable "plugin_id" {
  description = "ID of the CSI plugin (csi_plugin id): the plugin_id of the volumes."
  type        = string
  default     = "seaweedfs"

  validation {
    pattern = "^[a-zA-Z0-9][a-zA-Z0-9_.-]*$"
  }
}

variable "stats_interval" {
  description = "How often the client asks the driver for the usage and the condition of the volumes it has staged or published (csi_plugin stats_interval); \"0s\" turns it off."
  type        = string
  default     = "1m"

  validation {
    pattern = "^[0-9]+(ms|s|m|h)$"
  }
}

variable "filer" {
  description = "Address of the filer (host:port, its HTTP port; the driver also uses port + 10000 for gRPC), or a comma separated list. Empty finds the filers in the native catalog (filer_service)."
  type        = string
  default     = ""
}

variable "filer_service" {
  description = "Service of the filer in the native catalog, when filer is empty: the seaweedfs pack registers <job>-filer."
  type        = string
  default     = "seaweedfs-filer"
}

variable "cache_capacity_mb" {
  description = "Local chunk cache of a mount in MB (-cacheCapacityMB); 0 turns it off. The cache is in the allocation directory."
  type        = number
  default     = 0
}

variable "driver_args" {
  description = "Extra arguments of the driver, e.g. [\"-concurrentWriters=32\"]."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Binaries
# ---------------------------------------------------------------------------

variable "binaries_artifact_url" {
  description = "URL of an archive with seaweedfs-csi-driver and seaweedfs-mount (built from the driver repository; it publishes images, not binaries), unpacked into the task directories. Empty uses driver_binary and mount_binary as they are on the node."
  type        = string
  default     = ""
}

variable "binaries_artifact_checksum" {
  description = "Checksum of binaries_artifact_url (type:value)."
  type        = string
  default     = ""
}

variable "driver_binary" {
  description = "Path of seaweedfs-csi-driver: absolute on the node, or relative to the task directory with binaries_artifact_url (local/seaweedfs-csi-driver)."
  type        = string
  default     = "/usr/local/bin/seaweedfs-csi-driver"

  validation {
    min_length = 1
  }
}

variable "mount_binary" {
  description = "Path of seaweedfs-mount: absolute on the node, or relative to the task directory with binaries_artifact_url (local/seaweedfs-mount)."
  type        = string
  default     = "/usr/local/bin/seaweedfs-mount"

  validation {
    min_length = 1
  }
}

variable "weed_artifact_url" {
  description = "URL of the SeaweedFS release archive whose weed binary the mount service runs (weed mount). Use the release of the servers. Empty uses weed_binary as it is on the node."
  type        = string
  default     = "https://github.com/seaweedfs/seaweedfs/releases/download/4.51/linux_amd64.tar.gz"
}

variable "weed_artifact_checksum" {
  description = "Checksum of weed_artifact_url (type:value); the default is the md5 of linux_amd64.tar.gz of 4.51."
  type        = string
  default     = "md5:49f602d0d93ccf3e13607b3ccee8ffd6"
}

variable "weed_binary" {
  description = "Path of weed for the mount service: relative to the task directory with weed_artifact_url (local/weed), absolute on the node otherwise."
  type        = string
  default     = "local/weed"

  validation {
    min_length = 1
  }
}

# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------

variable "driver_resources" {
  description = "CPU (MHz) and memory (MB) of the driver."
  type = object({
    cpu    = number
    memory = number
  })
  default = {
    cpu    = 100
    memory = 256
  }
}

variable "mount_resources" {
  description = "CPU (MHz) and memory (MB) of the mount service and its weed mount processes (one per staged volume)."
  type = object({
    cpu    = number
    memory = number
  })
  default = {
    cpu    = 200
    memory = 512
  }
}
