# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0
[[- $v := vars . ]]
[[- $job := $v.job_name ]][[ if eq $job "" ]][[ $job = (meta "pack.name" .) ]][[ end ]]

# A single SeaweedFS server rendered by the seaweedfs pack: master, volume
# server and filer in one weed process (weed server -filer) with raw_exec,
# the data in data_dir of the node. The services <job>-master, <job>-volume
# and <job>-filer are in the native catalog; the seaweedfs-csi pack finds the
# filer there.
job [[ $job | quote ]] {
  [[- template "seaweedfs.location" . ]]
  type = "service"

  group "server" {
    count = 1

    # The data is on the node: the server never moves to another one.
    reschedule {
      attempts  = 0
      unlimited = false
    }

    network {
      port "master" {
        static = [[ $v.master_port ]]
      }
      port "master_grpc" {
        static = [[ add $v.master_port 10000 ]]
      }
      port "volume" {
        static = [[ $v.volume_port ]]
      }
      port "volume_grpc" {
        static = [[ add $v.volume_port 10000 ]]
      }
      port "filer" {
        static = [[ $v.filer_port ]]
      }
      port "filer_grpc" {
        static = [[ add $v.filer_port 10000 ]]
      }
    }

    service {
      name     = "[[ $job ]]-master"
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
      name     = "[[ $job ]]-volume"
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
      name     = "[[ $job ]]-filer"
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
      [[- if ne $v.artifact_url "" ]]

      artifact {
        source      = [[ $v.artifact_url | quote ]]
        destination = "local"
        [[- if ne $v.artifact_checksum "" ]]

        options {
          checksum = [[ $v.artifact_checksum | quote ]]
        }
        [[- end ]]
      }
      [[- end ]]

      config {
        command = "/bin/sh"
        args = [
          "-c",
          "mkdir -p [[ $v.data_dir ]] && exec [[ $v.binary ]] server \"$@\"",
          "weed",
          "-dir=[[ $v.data_dir ]]",
          "-ip=${NORCA_IP_master}",
          "-ip.bind=0.0.0.0",
          "-master.port=${NORCA_PORT_master}",
          "-master.defaultReplication=[[ $v.replication ]]",
          "-master.volumeSizeLimitMB=[[ $v.volume_size_limit_mb ]]",
          "-volume.port=${NORCA_PORT_volume}",
          "-volume.max=[[ $v.volume_max ]]",
          "-filer",
          "-filer.port=${NORCA_PORT_filer}",
          [[- range $a := $v.extra_args ]]
          [[ $a | quote ]],
          [[- end ]]
        ]
      }

      resources {
        cpu    = [[ $v.resources.cpu ]]
        memory = [[ $v.resources.memory ]]
      }
    }
  }
}
