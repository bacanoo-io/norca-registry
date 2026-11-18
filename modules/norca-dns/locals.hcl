# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

locals {
  mock   = var.driver == "mock_driver"
  docker = var.driver == "docker"

  # The flags of the operator.
  args = concat(
    [
      "-requeue", var.requeue,
      "-zone-token-namespace", var.zone_token_namespace,
      "-zone-ttl", var.zone_ttl,
      "-zone-allow-http=${var.zone_allow_http}",
    ],
    var.zone_ca_cert == "" ? [] : ["-zone-ca-file", "${runtime_env("NORCA_TASK_DIR")}/zone-ca.pem"],
    ["-log-level", var.log_level],
  )
}
