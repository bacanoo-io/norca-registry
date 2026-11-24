# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

locals {
  mock   = var.driver == "mock_driver"
  docker = var.driver == "docker"

  # The namespace of the tokens of the DNS zones: that of the job, the
  # namespace of the release, unless zone_token_namespace names another.
  tokens = var.zone_token_namespace != "" ? var.zone_token_namespace : rigger.namespace

  # Leader election (review finding CON-6e): asked for, or there are several
  # instances, which must not all place the orders. The lease is the
  # Variable controller-lease/<controller>, in the namespace of the job, the
  # namespace of the release, unless lease_namespace names another: the
  # operator would keep it in norca-system whatever its own namespace, so
  # the flag always names it.
  leader_election = var.leader_election || var.count > 1
  lease           = var.lease_namespace != "" ? var.lease_namespace : rigger.namespace
  lease_path      = "controller-lease/${var.controller}"

  # The Variables the ACL policy grants: the tokens of the DNS zones, which
  # the operator reads, and with leader election the lease, which every
  # instance reads, and writes with check-and-set to take, renew and release
  # the lead; it is never listed or deleted. Those of the namespace of the
  # job go into its block of the policy, the others into a block per
  # namespace.
  variable_grants = concat(
    [{ namespace = local.tokens, path = var.zone_token_path, capabilities = ["read"] }],
    local.leader_election ? [{ namespace = local.lease, path = local.lease_path, capabilities = ["read", "write"] }] : [],
  )
  variable_grants_here      = [for g in local.variable_grants : g if g.namespace == rigger.namespace]
  variable_grants_elsewhere = { for g in local.variable_grants : g.namespace => g... if g.namespace != rigger.namespace }

  # The CA files of the task: the ACME directory's and the DNS providers'.
  ca_files = local.mock ? [] : concat(
    var.acme_ca_cert == "" ? [] : [{ cert = var.acme_ca_cert, file = "local/acme-ca.pem" }],
    var.zone_ca_cert == "" ? [] : [{ cert = var.zone_ca_cert, file = "local/zone-ca.pem" }],
  )

  # The flags of the operator.
  args = concat(
    [
      "-controller", var.controller,
      "-interval", var.interval,
      "-http01-listen", var.http01_enabled ? ":${runtime_env("NORCA_PORT_http01")}" : "",
      "-secret-namespace", rigger.namespace,
      "-secret-prefix", var.secret_prefix,
      "-zone-token-namespace", local.tokens,
      "-zone-ttl", var.zone_ttl,
      "-zone-allow-http=${var.zone_allow_http}",
    ],
    local.leader_election ? ["-leader-election", "-lease-namespace", local.lease] : [],
    var.http01_settle == "" ? [] : ["-http01-settle", var.http01_settle],
    var.zone_ca_cert == "" ? [] : ["-zone-ca-file", "${runtime_env("NORCA_TASK_DIR")}/zone-ca.pem"],
    var.dns_resolver == "" ? [] : ["-dns-resolver", var.dns_resolver],
    [
      "-dns-propagation-check=${var.dns_propagation_check}",
      "-dns-propagation-timeout", var.dns_propagation_timeout,
    ],
    var.acme_ca_cert == "" ? [] : ["-acme-ca-file", "${runtime_env("NORCA_TASK_DIR")}/acme-ca.pem"],
    [
      "-retry-base", var.retry_base,
      "-retry-max", var.retry_max,
      "-max-attempts", tostring(var.max_attempts),
      "-log-level", var.log_level,
    ],
  )

  # The router of the Traefik module for the HTTP-01 challenge (acme_challenge
  # = true there): the path of the challenge of every host, on the http
  # entrypoints, to this service.
  http01_tags = length(var.http01_entrypoints) == 0 ? null : [
    "traefik.enable=true",
    "traefik.http.routers.${var.job_name}.rule=PathPrefix(`/.well-known/acme-challenge/`)",
    "traefik.http.routers.${var.job_name}.entrypoints=${join(",", var.http01_entrypoints)}",
    "traefik.http.routers.${var.job_name}.priority=2147483000",
  ]
}
