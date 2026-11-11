<!--
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
-->

# seaweedfs

A single [SeaweedFS](https://github.com/seaweedfs/seaweedfs) server: master,
volume server and filer in one `weed server -filer` process, with
**raw_exec** on one node, the data in a directory of that node. It is the
storage of the [seaweedfs-csi](../seaweedfs-csi/README.md) pack (CSI volumes
for the tasks of the cluster) and fits a test cluster or a small
installation; it keeps one copy of the data.

## License and binary

SeaweedFS is **Apache-2.0** software by the SeaweedFS authors
([LICENSE](https://github.com/seaweedfs/seaweedfs/blob/master/LICENSE)).
Norca does not ship it: the pack downloads the release archive on the node.

| | |
| --- | --- |
| Default archive | release [4.51](https://github.com/seaweedfs/seaweedfs/releases/tag/4.51) (2026-10-25), `linux_amd64.tar.gz` |
| Checksum | md5 `49f602d0d93ccf3e13607b3ccee8ffd6` (the `.md5` of the release) |

Mirror the archive for air-gapped clusters (`artifact_url`), or install
`weed` on the node and set `artifact_url = ""` and `binary`.

## Prerequisites

- The raw_exec driver enabled on the node of the server.
- The ports of the master, the volume server and the filer, and each + 10000
  (gRPC), open to the nodes that mount volumes (the seaweedfs-csi pack).
- Pin the server to one node with `node`: its data is in `data_dir` there.

## Variables

| Variable | Default | |
| --- | --- | --- |
| `node` | `""` | the node of the server (`node.unique.name`) |
| `data_dir` | `/var/lib/seaweedfs` | data of master, volume server and filer |
| `master_port`, `volume_port`, `filer_port` | 9333, 8080, 8888 | HTTP ports; gRPC is + 10000 |
| `replication` | `000` | default replication; one server keeps one copy |
| `volume_size_limit_mb` | 1024 | size of a volume file |
| `volume_max` | 0 | number of volume files; 0: from the free space |
| `artifact_url`, `artifact_checksum`, `binary` | release 4.51 | the weed binary |
| `extra_args` | `[]` | more `weed server` flags |

## Checks

- `curl http://<node>:9333/cluster/status`: the master is the leader.
- The services `seaweedfs-master`, `seaweedfs-volume` (HTTP checks) and
  `seaweedfs-filer` (TCP check) are passing in the native catalog.

## Limitations

- One server: no replication across nodes, no failover. Several masters,
  volume servers on many nodes and a filer store in a database are a later
  version of the pack.
- raw_exec only (no Docker variant yet).
