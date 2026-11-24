# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

locals {
  mock   = var.driver == "mock_driver"
  docker = var.driver == "docker"

  # The namespace of the tokens of the DNS zones: that of the job, the
  # namespace of the release, unless zone_token_namespace names another.
  tokens      = var.zone_token_namespace != "" ? var.zone_token_namespace : rigger.namespace
  tokens_here = local.tokens == rigger.namespace

  # Leader election (review finding CON-6e): asked for, or there are several
  # instances, which must not all write the zones. The lease is the Variable
  # controller-lease/<the name of the controller>, norca-dns, in the
  # namespace of the job: the operator would keep it in norca-system
  # whatever its own namespace, so the flag names it.
  leader_election = var.leader_election || var.count > 1
  lease_path      = "controller-lease/norca-dns"

  # The flags of the operator.
  args = concat(
    [
      "-requeue", var.requeue,
      "-zone-token-namespace", local.tokens,
      "-zone-ttl", var.zone_ttl,
      "-zone-allow-http=${var.zone_allow_http}",
    ],
    var.zone_ca_cert == "" ? [] : ["-zone-ca-file", "${runtime_env("NORCA_TASK_DIR")}/zone-ca.pem"],
    local.leader_election ? ["-leader-election", "-lease-namespace", rigger.namespace] : [],
    ["-log-level", var.log_level],
  )
}
