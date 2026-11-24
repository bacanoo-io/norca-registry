# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

output "job" {
  value       = var.job_name
  description = "ID of the job and of its HTTP-01 service; the ACL policy of the same name is bound to it."
}

output "controller" {
  value       = var.controller
  description = "The controller name the issuers give."
}

output "notes" {
  value       = <<-EOT
    norca-acme "${var.job_name}" in namespace ${rigger.namespace}: driver ${var.driver}, controller name "${var.controller}".

    It is the controller of the issuers that name it:
      kind = "norca.io/CertificateIssuer"
      name = "letsencrypt"
      spec {
        external {
          controller = "${var.controller}"
          config {
            directory = "https://acme-v02.api.letsencrypt.org/directory"
            email     = "ops@example.com"
          }
        }
      }

      norca object list norca.io/CertificateIssuer
      norca object list norca.io/CertificateOrder
    %{if var.http01_enabled}
    HTTP-01: the service "${var.job_name}" answers /.well-known/acme-challenge/%{if length(var.http01_entrypoints) > 0}
    and routes it on the Traefik entrypoints ${join(", ", var.http01_entrypoints)} (the Traefik module needs
    acme_challenge = true and the namespace ${rigger.namespace} in catalog_namespaces).%{else}
    Route that path of every host on port 80 to the service.%{endif}
    %{endif}
    DNS-01: for the names of the norca.io/DNSZone objects norca-provider
    registers (always for a wildcard):
      norca object list norca.io/DNSZone
  EOT
  description = "How to use the controller."
}
