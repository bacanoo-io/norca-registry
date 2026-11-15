[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
[[- if $v.zone_kind_enabled ]]
# The registry of the DNS zones (provider/dns/dnszone.kind.hcl of
# norca-platform). norca-provider registers each zone of a dns section and
# reports a heartbeat in status.heartbeat while it runs; norca-acme proves
# the names of a zone with the DNS-01 challenge through its provider.
kind "DNSZone" {
  group       = "norca.io"
  description = "A DNS zone a provider writes challenge records in, and where the operator calls it"
  namespaced  = false
  version     = 1
  schema      = <<EOT
{
  "type": "object",
  "properties": {
    "spec": {
      "type": "object",
      "required": ["zone", "endpoint"],
      "additionalProperties": false,
      "properties": {
        "zone":          {"type": "string", "pattern": "^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$", "description": "Name of the zone, lower case, without the dot at the end"},
        "provider":      {"type": "string", "description": "Name of the provider of the norca-provider configuration that serves the zone"},
        "endpoint":      {"type": "string", "pattern": "^https?://", "description": "Base URL of the DNS contract of the zone"},
        "tokenVariable": {"type": "string", "description": "Path of the Variable whose item token is the bearer token of the calls"},
        "parameters":    {"type": "object", "description": "Published settings of the provider; never a secret"}
      }
    },
    "status": {
      "type": "object",
      "properties": {
        "heartbeat": {"type": "string", "description": "RFC 3339 time of the last heartbeat"},
        "version":   {"type": "string"}
      }
    }
  }
}
EOT

  columns {
    column "Provider" { path = "spec.provider" }
    column "Endpoint" { path = "spec.endpoint" }
    column "Last seen" { path = "status.heartbeat" }
  }
}
[[- end ]]
