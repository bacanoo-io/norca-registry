# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

output "service" {
  value       = local.job
  description = "The admin entrypoint in the native catalog; each entrypoint is <service>-<entrypoint>."
}

output "entrypoints" {
  value       = { for e in var.entrypoints : e.name => e.port }
  description = "The ports of the entrypoints by name."
}

output "notes" {
  value = join("\n", concat(
    [
      "Traefik \"${local.job}\" (${var.job_type == "system" ? "on every node" : "${var.count} instances on different nodes"}${var.node_pool != "" ? " of the node pool ${var.node_pool}" : ""}).",
      "",
      "Entrypoints${var.host_network != "" ? " (host network ${var.host_network})" : ""}:",
    ],
    [for e in var.entrypoints : "  ${e.name}: ${e.port}/${e.protocol}${e.redirect_to != "" ? " -> redirected to ${e.redirect_to}" : ""}"],
    [
      "  traefik (admin): ${var.admin_port}: /ping${var.dashboard ? ", /dashboard/" : ""}${var.metrics ? ", /metrics" : ""} (keep it closed to the outside)",
      "",
    ],
    length(var.tls_certificates) > 0 ? [
      "Certificates from the secret store (items ${var.tls_cert_item} and ${var.tls_key_item}): ${join(", ", var.tls_certificates)}",
      ] : [
      "No certificate configured: the https entrypoints serve Traefik's self-signed default certificate. Store one and add it to tls_certificates:",
      "  norca secret put traefik/certs/example-com cert=@fullchain.pem key=@privkey.pem",
    ],
    var.catalog_enabled ? split("\n", <<-EOT

      Routing a service of the catalog (namespaces ${join(", ", var.catalog_namespaces)}):
        service {
          name     = "app"
          port     = "http"
          provider = "nomad"
          tags = [
            "traefik.enable=true",
            "traefik.http.routers.app.rule=Host(`app.example.com`)",
            "traefik.http.routers.app.entrypoints=websecure",
          ]
        }

      The workload identity of Traefik reads the services of its own namespace. For the other namespaces bind a policy to the job:
        namespace "*" {
          capabilities = ["read-job"]
        }
        norca acl policy apply -namespace ${rig.namespace} -job ${local.job} traefik-catalog policy.hcl
    EOT
    ) : [],
  ))
  description = "The entrypoints and how to route a service."
}
