[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
norca-acme "[[ $v.job_name ]]" in namespace [[ $v.namespace ]]: driver [[ $v.driver ]], controller name "[[ $v.controller ]]".

It is the controller of the issuers that name it:
  kind = "norca.io/CertificateIssuer"
  name = "letsencrypt"
  spec {
    external {
      controller = "[[ $v.controller ]]"
      config {
        directory = "https://acme-v02.api.letsencrypt.org/directory"
        email     = "ops@example.com"
      }
    }
  }

  norca object list norca.io/CertificateIssuer
  norca object list norca.io/CertificateOrder
[[- if $v.http01_enabled ]]

HTTP-01: the service "[[ $v.job_name ]]" answers /.well-known/acme-challenge/[[ if gt (len $v.http01_entrypoints) 0 ]]
and routes it on the Traefik entrypoints [[ join ", " $v.http01_entrypoints ]] (the Traefik pack needs
acme_challenge = true and the namespace [[ $v.namespace ]] in catalog_namespaces).[[ else ]]
Route that path of every host on port 80 to the service.[[ end ]]
[[- end ]]

DNS-01: for the names of the norca.io/DNSZone objects norca-provider
registers (always for a wildcard):
  norca object list norca.io/DNSZone
