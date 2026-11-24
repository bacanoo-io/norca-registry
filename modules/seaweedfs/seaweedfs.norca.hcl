# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# A single SeaweedFS server: master, volume server and filer in one weed
# process (weed server -filer) with raw_exec, the data in data_dir of the
# node. The services <job>-master, <job>-volume and <job>-filer are in the
# native catalog; the seaweedfs-csi module finds the filer there.
job "seaweedfs" {
  id          = local.job
  name        = local.job
  region      = rigger.region
  datacenters = module.placement.datacenters
  node_pool   = module.placement.node_pool
  type        = "service"

  dynamic "constraint" {
    for_each = module.placement.constraints

    content {
      attribute = constraint.value.attribute
      operator  = constraint.value.operator
      value     = constraint.value.value
    }
  }

  group "server" {
    count = 1

    # The data is on the node: the server never moves to another one.
    reschedule {
      attempts  = 0
      unlimited = false
    }

    network {
      port "master" {
        static = var.master_port
      }
      port "master_grpc" {
        static = var.master_port + 10000
      }
      port "volume" {
        static = var.volume_port
      }
      port "volume_grpc" {
        static = var.volume_port + 10000
      }
      port "filer" {
        static = var.filer_port
      }
      port "filer_grpc" {
        static = var.filer_port + 10000
      }
    }

    service {
      name     = "${local.job}-master"
      provider = "nomad"
      port     = "master"

      check {
        type     = "http"
        path     = "/cluster/status"
        interval = "10s"
        timeout  = "3s"
      }
    }

    service {
      name     = "${local.job}-volume"
      provider = "nomad"
      port     = "volume"

      check {
        type     = "http"
        path     = "/status"
        interval = "10s"
        timeout  = "3s"
      }
    }

    service {
      name     = "${local.job}-filer"
      provider = "nomad"
      port     = "filer"

      check {
        type     = "tcp"
        interval = "10s"
        timeout  = "3s"
      }
    }

    task "weed" {
      driver = "raw_exec"

      dynamic "artifact" {
        for_each = var.artifact_url == "" ? [] : [var.artifact_url]

        content {
          source      = artifact.value
          destination = "local"

          dynamic "options" {
            for_each = var.artifact_checksum == "" ? [] : [var.artifact_checksum]

            content {
              checksum = options.value
            }
          }
        }
      }

      config {
        command = "/bin/sh"
        args = concat([
          "-c",
          "mkdir -p ${var.data_dir} && exec ${var.binary} server \"$@\"",
          "weed",
          "-dir=${var.data_dir}",
          "-ip=${runtime_env("NORCA_IP_master")}",
          "-ip.bind=0.0.0.0",
          "-master.port=${runtime_env("NORCA_PORT_master")}",
          "-master.defaultReplication=${var.replication}",
          "-master.volumeSizeLimitMB=${var.volume_size_limit_mb}",
          "-volume.port=${runtime_env("NORCA_PORT_volume")}",
          "-volume.max=${var.volume_max}",
          "-filer",
          "-filer.port=${runtime_env("NORCA_PORT_filer")}",
        ], var.extra_args)
      }

      resources {
        cpu    = var.resources.cpu
        memory = var.resources.memory
      }
    }
  }
}
