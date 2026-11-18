# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

locals {
  # The ID of the job and the name of its service; empty is the release.
  job         = coalesce(var.job_name, rig.release)
  distributed = var.mode == "distributed"

  # The drives of a distributed store: one endpoint per node.
  endpoints = [for n in var.nodes : "http://${n}:${var.s3_port}/data"]

  otlp = trimsuffix(var.otlp_endpoint, "/")

  # Listen address, drives, S3 region, console; an empty log directory sends
  # the logs to stdout (the task logs).
  env = merge(
    {
      RUSTFS_ADDRESS           = ":${var.s3_port}"
      RUSTFS_VOLUMES           = local.distributed ? join(" ", local.endpoints) : "/data"
      RUSTFS_REGION            = var.s3_region
      RUSTFS_CONSOLE_ENABLE    = tostring(var.console_enabled)
      RUSTFS_OBS_LOGGER_LEVEL  = var.log_level
      RUSTFS_OBS_LOG_DIRECTORY = ""
    },
    local.distributed ? { RUSTFS_LOCAL_ENDPOINT_HOST = var.node_address_attribute } : {},
    var.console_enabled ? { RUSTFS_CONSOLE_ADDRESS = ":${var.console_port}" } : {},
    # OTLP/HTTP export of the signals below only (a per-signal endpoint is
    # used as it is; logs keep going to stdout).
    var.metrics_enabled || var.traces_enabled ? { RUSTFS_OBS_SERVICE_NAME = local.job } : {},
    var.metrics_enabled ? { RUSTFS_OBS_METRIC_ENDPOINT = "${local.otlp}/v1/metrics" } : {},
    var.traces_enabled ? { RUSTFS_OBS_TRACE_ENDPOINT = "${local.otlp}/v1/traces" } : {},
    var.extra_env,
  )
}
