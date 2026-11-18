# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

output "service" {
  value       = local.job
  description = "The client service in the native catalog."
}

output "client_port" {
  value       = var.client_port
  description = "The client port; 0 is a dynamic port."
}

output "accounts" {
  value       = local.userpass ? local.accounts : []
  description = "The accounts of the users (auth_mode userpass)."
}

output "jetstream_domain" {
  value       = var.jetstream_enabled && var.jetstream_domain != "" ? var.jetstream_domain : null
  description = "The JetStream domain of the cluster, or null."
}

output "notes" {
  value = join("\n", concat(
    [
      "NATS job \"${local.job}\": ${var.count} server(s), driver ${var.driver}, JetStream ${var.jetstream_enabled ? "on (${var.storage})" : "off"}, TLS ${var.tls_enabled ? "on" : "off"}, auth ${var.auth_mode}.",
      "",
      "Services (native discovery, namespace ${rig.namespace}):",
      "  ${local.job}            clients          norca service info ${local.job}",
      "  ${local.job}-cluster    routes",
    ],
    var.gateway_enabled ? ["  ${local.job}-gateway    gateway address the other regions list in remote_gateways"] : [],
    ["  ${local.job}-monitor    monitoring       curl http://<addr>/routez /jsz /gatewayz /healthz"],
    local.userpass ? concat(
      [
        "",
        "Users (auth_mode userpass): the servers wait for one secret per user in the",
        "namespace ${rig.namespace} (item password: plain, or a bcrypt hash of nats server passwd).",
        "A new version is applied with a reload of the servers:",
      ],
      [for u in var.users : "  norca secret put -namespace ${rig.namespace} ${var.users_secret_prefix}/${u.name} password=-      # account ${coalesce(u.account, var.users_default_account)}"],
    ) : [],
    var.tls_enabled || (var.auth_mode != "none" && !local.userpass) ? concat(
      [
        "",
        "The servers start only when the Variable ${local.secrets} exists, e.g.:",
        "  norca var put -namespace ${rig.namespace} ${local.secrets} \\",
      ],
      var.tls_enabled ? ["    tls_ca=@ca.pem tls_cert=@server.pem tls_key=@server-key.pem \\"] : [],
      var.auth_mode == "token" ? ["    client_token=<token>"] : var.auth_mode == "nkey" ? ["    client_nkeys=<UA...,UB...>"] : var.auth_mode == "config" ? ["    auth_config=@auth.conf"] : [],
    ) : [],
  ))
  description = "The services, and the secrets and Variable the servers wait for."
}
