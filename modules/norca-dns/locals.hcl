# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

locals {
  mock   = var.driver == "mock_driver"
  docker = var.driver == "docker"

  # The namespace of the tokens of the DNS zones: that of the job, the
  # namespace of the release, unless zone_token_namespace names another.
  tokens = var.zone_token_namespace != "" ? var.zone_token_namespace : rigger.namespace

  # The flags of the operator.
  args = concat(
    [
      "-requeue", var.requeue,
      "-zone-token-namespace", local.tokens,
      "-zone-ttl", var.zone_ttl,
      "-zone-allow-http=${var.zone_allow_http}",
    ],
    var.zone_ca_cert == "" ? [] : ["-zone-ca-file", "${runtime_env("NORCA_TASK_DIR")}/zone-ca.pem"],
    ["-log-level", var.log_level],
  )
}
