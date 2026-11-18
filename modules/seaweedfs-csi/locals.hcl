# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

locals {
  # The ID of the job; empty is the release.
  job = coalesce(var.job_name, rig.release)

  # The archives of a task: what each one downloads, with its checksum.
  weed_artifacts     = var.weed_artifact_url == "" ? [] : [{ source = var.weed_artifact_url, checksum = var.weed_artifact_checksum }]
  binaries_artifacts = var.binaries_artifact_url == "" ? [] : [{ source = var.binaries_artifact_url, checksum = var.binaries_artifact_checksum }]

  # weed_binary is absolute on the node, or relative to the task directory
  # above NORCA_TASK_DIR (the local directory of the task).
  weed_binary = substr(var.weed_binary, 0, 1) == "/" ? var.weed_binary : "${runtime_env("NORCA_TASK_DIR")}/../${var.weed_binary}"

  mount_socket = "unix://${runtime_env("NORCA_ALLOC_DIR")}/seaweedfs-mount.sock"
}
