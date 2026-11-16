[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
norca-dns "[[ $v.job_name ]]" in namespace [[ $v.namespace ]]: driver [[ $v.driver ]].

It keeps the record sets of the norca.io/DNSRecord objects:
  kind      = "norca.io/DNSRecord"
  name      = "shop"
  namespace = "team-a"
  spec {
    name   = "shop.team-a.example.com"
    type   = "A"
    values = ["203.0.113.10"]
  }

A namespace writes names under its allow list only (the namespace metadata
norca.io/dns-suffixes, or dns_suffixes of a Tenant), in the zones of
norca-provider whose configuration says records = true:
  norca object list norca.io/DNSZone
  norca object list -namespace "*" norca.io/DNSRecord
