# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

locals {
  # The ID of the job and the name of its admin service; empty is the
  # release.
  job  = coalesce(var.job_name, rig.release)
  host = var.network_mode == "host"

  certs           = var.tls_certificates
  default_cert    = var.tls_default_certificate == "" && length(local.certs) > 0 ? local.certs[0] : var.tls_default_certificate
  cert_secrets    = local.default_cert != "" && !contains(local.certs, local.default_cert) ? concat(local.certs, [local.default_cert]) : local.certs
  entrypoint_port = { for e in var.entrypoints : e.name => e.port }
  redirects       = [for e in var.entrypoints : e if e.redirect_to != ""]

  # The port label of an entrypoint.
  labels = { for e in var.entrypoints : e.name => "ep_${replace(e.name, "-", "_")}" }

  # The static configuration: entrypoints, providers, logs.
  static_config = join("\n", concat(
    [
      "global:",
      "  checkNewVersion: false",
      "  sendAnonymousUsage: false",
      "log:",
      "  level: ${var.log_level}",
    ],
    var.access_log ? ["accessLog: {}"] : [],
    [
      "entryPoints:",
      "  traefik:",
      "    address: \"${local.host ? "{{ env \"NORCA_IP_admin\" }}" : ""}:${var.admin_port}\"",
    ],
    flatten([for e in var.entrypoints : concat(
      [
        "  ${e.name}:",
        "    address: \"${local.host ? "{{ env \"NORCA_IP_${local.labels[e.name]}\" }}" : ""}:${e.port}${e.protocol == "udp" ? "/udp" : ""}\"",
      ],
      e.redirect_to != "" && !var.acme_challenge ? [
        "    http:",
        "      redirections:",
        "        entryPoint:",
        "          to: ${e.redirect_to}",
        "          scheme: https",
        "          permanent: true",
        ] : e.protocol == "https" ? [
        "    http:",
        "      tls: {}",
      ] : [],
    )]),
    ["ping:", "  entryPoint: traefik"],
    var.dashboard ? ["api:", "  dashboard: true", "  insecure: true"] : [],
    var.metrics ? ["metrics:", "  prometheus:", "    entryPoint: traefik"] : [],
    [
      "providers:",
      "  file:",
      "    directory: \"{{ env \"NORCA_SECRETS_DIR\" }}/dynamic\"",
      "    watch: true",
    ],
    var.catalog_enabled ? [
      "  nomad:",
      "    exposedByDefault: ${var.exposed_by_default}",
      "    namespaces: ${jsonencode(var.catalog_namespaces)}",
      "    endpoint:",
      "      address: \"${var.nomad_address != "" ? var.nomad_address : "unix://{{ env \"NORCA_SECRETS_DIR\" }}/api.sock"}\"",
      "      token: \"{{ env \"NORCA_TOKEN\" }}\"",
    ] : [],
  ))

  # TLS: the options, and the certificates of the secret store as the PEM
  # content of certFile and keyFile; Traefik takes the content as well as a
  # path. A missing secret fails the template, so the allocation does not
  # start with a wrong certificate.
  tls_config = join("\n", concat(
    ["tls:", "  options:", "    default:", "      minVersion: ${var.tls_min_version}"],
    length(local.certs) > 0 ? ["  certificates:"] : [],
    flatten([for p in local.certs : local.certificate[p]["    - "]]),
    local.default_cert != "" ? concat(["  stores:", "    default:", "      defaultCertificate:"], local.certificate[local.default_cert]["        "]) : [],
  ))

  # The lines of each certificate, by the text before certFile: in the
  # list of certificates ("    - ", PEM indented by 8) or as the default
  # one ("        ", PEM indented by 10).
  certificate = {
    for p in local.cert_secrets : p => {
      for first, layout in { "    - " = { next = "      ", pem = 8 }, "        " = { next = "        ", pem = 10 } } : first => [
        "${first}certFile: |",
        "{{ with nomadSecret \"${p}\" }}{{ index . \"${var.tls_cert_item}\" | trimSpace | indent ${layout.pem} }}{{ else }}{{ sprig_fail \"the secret ${p} does not exist\" }}{{ end }}",
        "${layout.next}keyFile: |",
        "{{ with nomadSecret \"${p}\" }}{{ index . \"${var.tls_key_item}\" | trimSpace | indent ${layout.pem} }}{{ end }}",
      ]
    }
  }

  # The redirect to https as a router, so that it can leave out the path of
  # the ACME HTTP-01 challenge.
  redirect_config = join("\n", concat(
    ["http:", "  routers:"],
    flatten([for e in local.redirects : [
      "    redirect-${e.name}:",
      "      entryPoints: ${jsonencode([e.name])}",
      "      rule: \"!PathPrefix(`/.well-known/acme-challenge/`)\"",
      "      priority: 2147483000",
      "      middlewares: ${jsonencode(["redirect-${e.name}"])}",
      "      service: noop@internal",
    ]]),
    ["  middlewares:"],
    flatten([for e in local.redirects : [
      "    redirect-${e.name}:",
      "      redirectScheme:",
      "        scheme: https",
      "        port: \"${local.entrypoint_port[e.redirect_to]}\"",
      "        permanent: true",
    ]]),
  ))

  # mTLS to the backends: a servers transport per backend with the workload
  # certificate and the trust bundle as PEM content.
  mtls_config = join("\n", concat(
    ["http:", "  serversTransports:"],
    flatten([for b in var.mtls_backends : [
      "    mtls-${b.name}:",
      "      serverName: \"${b.service}.service.${b.namespace != "" ? b.namespace : rig.namespace}.norca\"",
      "      rootCAs:",
      "        - |",
      "{{ file (env \"NORCA_MTLS_CA_FILE\") | trimSpace | indent 10 }}",
      "      certificates:",
      "        - certFile: |",
      "{{ file (env \"NORCA_MTLS_CERT_FILE\") | trimSpace | indent 12 }}",
      "          keyFile: |",
      "{{ file (env \"NORCA_MTLS_KEY_FILE\") | trimSpace | indent 12 }}",
    ]]),
  ))
}
