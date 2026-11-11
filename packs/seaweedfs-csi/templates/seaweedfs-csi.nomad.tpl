# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0
[[- $v := vars . ]]
[[- $job := $v.job_name ]][[ if eq $job "" ]][[ $job = (meta "pack.name" .) ]][[ end ]]

# The SeaweedFS CSI driver on every node, rendered by the seaweedfs-csi pack.
# Both tasks run with raw_exec on the host file system: the mount service
# starts the weed mount (FUSE) processes, the driver is the CSI plugin
# (controller and node in one process) and asks the mount service over a
# socket in the allocation directory. Norca hands a raw_exec plugin the host
# paths to stage and publish, so neither task needs a privileged container.
job [[ $job | quote ]] {
  [[- if ne $v.region "" ]]
  region = [[ $v.region | quote ]]
  [[- end ]]
  [[- if ne $v.namespace "" ]]
  namespace = [[ $v.namespace | quote ]]
  [[- end ]]
  datacenters = [[ $v.datacenters | toStringList ]]
  [[- if ne $v.node_pool "" ]]
  node_pool = [[ $v.node_pool | quote ]]
  [[- end ]]
  type = "system"
  [[- range $c := $v.constraints ]]

  constraint {
    attribute = [[ $c.attribute | quote ]]
    operator  = [[ $c.operator | quote ]]
    [[- if ne $c.value "" ]]
    value = [[ $c.value | quote ]]
    [[- end ]]
  }
  [[- end ]]

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
      [[- if ne $v.weed_artifact_url "" ]]

      artifact {
        source      = [[ $v.weed_artifact_url | quote ]]
        destination = "local"
        [[- if ne $v.weed_artifact_checksum "" ]]

        options {
          checksum = [[ $v.weed_artifact_checksum | quote ]]
        }
        [[- end ]]
      }
      [[- end ]]
      [[- if ne $v.binaries_artifact_url "" ]]

      artifact {
        source      = [[ $v.binaries_artifact_url | quote ]]
        destination = "local"
        [[- if ne $v.binaries_artifact_checksum "" ]]

        options {
          checksum = [[ $v.binaries_artifact_checksum | quote ]]
        }
        [[- end ]]
      }
      [[- end ]]

      config {
        command = [[ $v.mount_binary | quote ]]
        args = [
          "-endpoint=unix://${NORCA_ALLOC_DIR}/seaweedfs-mount.sock",
          [[- if hasPrefix "/" $v.weed_binary ]]
          "-weedBinary=[[ $v.weed_binary ]]",
          [[- else ]]
          # NORCA_TASK_DIR is the local directory of the task: weed_binary is
          # relative to the task directory above it.
          "-weedBinary=${NORCA_TASK_DIR}/../[[ $v.weed_binary ]]",
          [[- end ]]
        ]
      }

      resources {
        cpu    = [[ $v.mount_resources.cpu ]]
        memory = [[ $v.mount_resources.memory ]]
      }
    }

    # The CSI plugin: controller and node.
    task "plugin" {
      driver = "raw_exec"
      [[- if ne $v.binaries_artifact_url "" ]]

      artifact {
        source      = [[ $v.binaries_artifact_url | quote ]]
        destination = "local"
        [[- if ne $v.binaries_artifact_checksum "" ]]

        options {
          checksum = [[ $v.binaries_artifact_checksum | quote ]]
        }
        [[- end ]]
      }
      [[- end ]]
      [[- if eq $v.filer "" ]]

      # The filers of the native catalog; a change restarts the driver.
      template {
        destination = "local/filer.env"
        env         = true
        change_mode = "restart"
        data        = <<-EOF
          SEAWEEDFS_FILER={{ range $i, $s := nomadService [[ $v.filer_service | quote ]] }}{{ if $i }},{{ end }}{{ $s.Address }}:{{ $s.Port }}{{ end }}
        EOF
      }
      [[- end ]]

      config {
        command = [[ $v.driver_binary | quote ]]
        args = [
          "-endpoint=${CSI_ENDPOINT}",
          [[- if eq $v.filer "" ]]
          "-filer=${SEAWEEDFS_FILER}",
          [[- else ]]
          "-filer=[[ $v.filer ]]",
          [[- end ]]
          "-nodeid=${node.unique.name}",
          "-dataCenter=${node.datacenter}",
          "-components=controller,node",
          "-mountEndpoint=unix://${NORCA_ALLOC_DIR}/seaweedfs-mount.sock",
          "-cacheDir=${NORCA_ALLOC_DIR}/cache",
          "-cacheCapacityMB=[[ $v.cache_capacity_mb ]]",
          [[- range $a := $v.driver_args ]]
          [[ $a | quote ]],
          [[- end ]]
        ]
      }

      csi_plugin {
        id             = [[ $v.plugin_id | quote ]]
        type           = "monolith"
        mount_dir      = "/csi"
        stats_interval = [[ $v.stats_interval | quote ]]
      }

      resources {
        cpu    = [[ $v.driver_resources.cpu ]]
        memory = [[ $v.driver_resources.memory ]]
      }
    }
  }
}
