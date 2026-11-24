# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The SeaweedFS CSI driver on every node. Both tasks run with raw_exec on the
# host file system: the mount service starts the weed mount (FUSE)
# processes, the driver is the CSI plugin (controller and node in one
# process) and asks the mount service over a socket in the allocation
# directory. Norca hands a raw_exec plugin the host paths to stage and
# publish, so neither task needs a privileged container.
job "seaweedfs-csi" {
  id          = local.job
  name        = local.job
  region      = rigger.region
  datacenters = module.placement.datacenters
  node_pool   = module.placement.node_pool
  type        = "system"

  dynamic "constraint" {
    for_each = module.placement.constraints

    content {
      attribute = constraint.value.attribute
      operator  = constraint.value.operator
      value     = constraint.value.value
    }
  }

  # One node at a time: the mounts of a node go away while its plugin
  # restarts.
  update {
    max_parallel = 1
  }

  group "csi" {
    # The mount service: runs weed mount for every staged volume.
    task "mount" {
      driver = "raw_exec"

      lifecycle {
        hook    = "prestart"
        sidecar = true
      }

      dynamic "artifact" {
        for_each = concat(local.weed_artifacts, local.binaries_artifacts)

        content {
          source      = artifact.value.source
          destination = "local"

          dynamic "options" {
            for_each = artifact.value.checksum == "" ? [] : [artifact.value.checksum]

            content {
              checksum = options.value
            }
          }
        }
      }

      config {
        command = var.mount_binary
        args    = ["-endpoint=${local.mount_socket}", "-weedBinary=${local.weed_binary}"]
      }

      resources {
        cpu    = var.mount_resources.cpu
        memory = var.mount_resources.memory
      }
    }

    # The CSI plugin: controller and node.
    task "plugin" {
      driver = "raw_exec"

      dynamic "artifact" {
        for_each = local.binaries_artifacts

        content {
          source      = artifact.value.source
          destination = "local"

          dynamic "options" {
            for_each = artifact.value.checksum == "" ? [] : [artifact.value.checksum]

            content {
              checksum = options.value
            }
          }
        }
      }

      # The filers of the native catalog; a change restarts the driver.
      dynamic "template" {
        for_each = var.filer == "" ? [var.filer_service] : []

        content {
          destination = "local/filer.env"
          env         = true
          change_mode = "restart"
          data        = <<-EOF
            SEAWEEDFS_FILER={{ range $i, $s := nomadService "${template.value}" }}{{ if $i }},{{ end }}{{ $s.Address }}:{{ $s.Port }}{{ end }}
          EOF
        }
      }

      config {
        command = var.driver_binary
        args = concat([
          "-endpoint=${runtime_env("CSI_ENDPOINT")}",
          var.filer == "" ? "-filer=${runtime_env("SEAWEEDFS_FILER")}" : "-filer=${var.filer}",
          "-nodeid=${runtime("node.unique.name")}",
          "-dataCenter=${runtime("node.datacenter")}",
          "-components=controller,node",
          "-mountEndpoint=${local.mount_socket}",
          "-cacheDir=${runtime_env("NORCA_ALLOC_DIR")}/cache",
          "-cacheCapacityMB=${var.cache_capacity_mb}",
        ], var.driver_args)
      }

      csi_plugin {
        id             = var.plugin_id
        type           = "monolith"
        mount_dir      = "/csi"
        stats_interval = var.stats_interval
      }

      resources {
        cpu    = var.driver_resources.cpu
        memory = var.driver_resources.memory
      }
    }
  }
}
