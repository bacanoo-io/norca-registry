<!--
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
-->

# seaweedfs-csi

The [SeaweedFS CSI driver](https://github.com/bacanoo-io/seaweedfs-csi-driver)
on every node: volumes of a [SeaweedFS](https://github.com/seaweedfs/seaweedfs)
filer (the [seaweedfs](../seaweedfs/README.md) pack, or any other) for the
tasks of the cluster, created, mounted and expanded through Norca's
[CSI volumes](https://github.com/bacanoo-io/norca-doc).

One system job with two tasks, both **raw_exec** on the host file system, so
no privileged container is needed:

- `mount`: the mount service (`seaweedfs-mount`), a prestart sidecar. It
  runs a `weed mount` (FUSE) process for every volume staged on the node.
- `plugin`: the driver (`seaweedfs-csi-driver`) as a monolith CSI plugin
  (controller and node). It asks the mount service over a socket in the
  allocation directory. Norca hands a raw_exec plugin the host paths to stage
  and publish volumes (Norca with the host path change of CSI completion
  phase 2).

The driver reports the **usage of every staged and published volume**
(`GET_VOLUME_STATS`) and, from the fork's release with `VOLUME_CONDITION`,
its **condition**: a volume whose FUSE mount does not answer is abnormal.
Norca shows both in `norca volume status`, keeps the `norca.volume.*`
metrics and publishes `VolumeAbnormal` and `VolumeRecovered` events (see
`csi_plugin` `stats_interval`).

## License and binaries

The driver is **Apache-2.0** software (the SeaweedFS authors; the fork
`bacanoo-io/seaweedfs-csi-driver` adds the volume condition), SeaweedFS
itself is **Apache-2.0** as well. Norca does not ship them: the pack runs
binaries that are on the nodes or downloads them.

| | |
| --- | --- |
| Driver and mount service | built from the driver repository (`go build ./cmd/seaweedfs-csi-driver ./cmd/seaweedfs-mount`); the repository publishes images, no binaries. Put them on the nodes (`driver_binary`, `mount_binary`) or in an archive (`binaries_artifact_url`). |
| weed (for `weed mount`) | release archive [4.51](https://github.com/seaweedfs/seaweedfs/releases/tag/4.51) (2026-10-25), `linux_amd64.tar.gz`, md5 `49f602d0d93ccf3e13607b3ccee8ffd6` (`weed_artifact_url`); use the release of the servers |

## Prerequisites

- Every node of the job: **FUSE 3** (`fuse3`: `/dev/fuse`, `fusermount3`) and
  the raw_exec driver enabled with `/dev/fuse` allowed. On cgroups v2 raw_exec
  tasks may only open a short list of devices; add FUSE to it:

  ```hcl
  plugin "raw_exec" {
    config {
      enabled         = true
      allowed_devices = ["/dev/fuse"]
    }
  }
  ```

  (norca-deployer: `client_settings.raw_exec_allowed_devices: [/dev/fuse]`.)
  The tasks run as the user of the Norca agent (root), which may mount.
- A filer: the `seaweedfs-filer` service of the seaweedfs pack in the same
  namespace, or `filer` set. The nodes reach the filer on its HTTP port and on
  port + 10000 (gRPC), and the volume servers the same way.
- Norca 0.3.0 or newer (raw_exec plugins get host paths, `stats_interval`,
  raw_exec `allowed_devices`).

## Variables

| Variable | Default | |
| --- | --- | --- |
| `plugin_id` | `seaweedfs` | ID of the plugin, the `plugin_id` of the volumes |
| `stats_interval` | `1m` | how often the usage and the condition are asked; `0s` off |
| `filer` | `""` | filer address(es); empty: `filer_service` from the native catalog |
| `filer_service` | `seaweedfs-filer` | |
| `driver_binary`, `mount_binary` | `/usr/local/bin/...` | the binaries on the node |
| `binaries_artifact_url` | `""` | an archive with both, instead |
| `weed_artifact_url`, `weed_binary` | release 4.51, `local/weed` | weed for the mount service |
| `cache_capacity_mb` | `0` | chunk cache of a mount |
| `driver_args` | `[]` | extra driver flags |
| `constraints`, `node_pool`, `datacenters` | | the nodes that get the plugin |

## Volumes

Create a volume through the controller (a directory `/buckets/<id>` of the
filer):

```hcl
id        = "data"
name      = "data"
type      = "csi"
plugin_id = "seaweedfs"

capacity_min = "1GiB"

capability {
  access_mode     = "multi-node-multi-writer"
  attachment_mode = "file-system"
}

parameters {
  replication = "000"
}
```

```shell
norca volume create data.hcl
norca volume status data          # after a task mounts it: Node Usage
```

## Checks

- `norca plugin status seaweedfs`: controllers and nodes healthy.
- `norca volume status <id>`: the Node Usage of the nodes where it is mounted
  (bytes, inodes, condition).
- The lab case `csi` of norca-lab installs both packs on one node and checks
  creation, mounting, the usage, the metrics and the events.

## Limitations

- raw_exec only (no Docker variant yet).
- The mounts of a node are interrupted while its job restarts (an update, a
  new binary): `update { max_parallel = 1 }` restarts one node at a time.
