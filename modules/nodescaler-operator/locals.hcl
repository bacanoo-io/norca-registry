# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

locals {
  mock   = var.driver == "mock_driver"
  docker = var.driver == "docker"

  # The flags of the operator.
  args = concat(
    [
      "-log-level", var.log_level,
      "-lease-namespace", rig.namespace,
      "-token-namespace", var.variables_namespace,
      "-bootstrap-namespace", var.variables_namespace,
      "-provider-ttl", var.provider_ttl,
      "-provider-allow-http=${var.provider_allow_http}",
      "-orphan-after", var.orphan_after,
      "-orphan-sweep", var.orphan_sweep,
      "-delete-orphans=${var.delete_orphans}",
      "-resync", var.resync,
    ],
    var.join_enabled ? concat([
      "-join-listen", ":${var.join_port}",
      "-join-validity", var.join_validity,
      "-join-check-address=${var.join_check_address}",
      "-join-key-store", var.join_key_store,
      "-join-service", "${var.job_name}-join",
      "-join-service-namespace", rig.namespace,
    ], flatten([for u in var.join_urls : ["-join-url", u]])) : [],
    # In a container the address of the host cannot be bound; the port is
    # mapped to the same port of the container.
    local.docker ? ["-metrics-addr", ":${runtime_env("NORCA_PORT_metrics")}"] : ["-metrics-addr", runtime_env("NORCA_ADDR_metrics")],
  )
}
