# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

locals {
  mock   = var.driver == "mock_driver"
  docker = var.driver == "docker"

  # The tokens of the DNS zones are in the namespace of the release.
  tokens_here = var.zone_token_namespace == rig.namespace

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
      "-secret-namespace", rig.namespace,
      "-secret-prefix", var.secret_prefix,
      "-zone-token-namespace", var.zone_token_namespace,
      "-zone-ttl", var.zone_ttl,
      "-zone-allow-http=${var.zone_allow_http}",
    ],
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
