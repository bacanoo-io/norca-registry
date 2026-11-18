[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
[[- if $v.record_kind_enabled ]]
# The DNS records (dnsrecord/dnsrecord.kind.hcl of norca-platform). norca-dns
# keeps the record set of each object in the zone of norca-provider that
# holds its name.
kind "DNSRecord" {
  group       = "norca.io"
  description = "A DNS record set kept by norca-dns in a zone of norca-provider"
  namespaced  = true
  version     = 1
  schema      = <<EOT
{
  "type": "object",
  "properties": {
    "spec": {
      "type": "object",
      "required": ["name", "type"],
      "additionalProperties": false,
      "properties": {
        "name":   {"type": "string", "minLength": 1, "maxLength": 253, "description": "Fully qualified name of the record set"},
        "type":   {"type": "string", "enum": ["A", "AAAA", "CNAME", "TXT"], "description": "Type of the record set"},
        "ttl":    {"type": "integer", "minimum": 0, "maximum": 86400, "description": "Time to live in seconds; 0 is 300"},
        "values": {"type": "array", "minItems": 1, "maxItems": 32, "items": {"type": "string", "minLength": 1, "maxLength": 255}, "description": "The values: addresses, one name for a CNAME, texts"},
        "source": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "load_balancer": {"type": "string", "minLength": 1, "description": "A LoadBalancer object of the namespace whose frontend addresses are the values"}
          }
        },
        "adopt":  {"type": "boolean", "description": "Take over a record set of the name and type that norca-dns did not write"},
        "deletion_policy": {"type": "string", "enum": ["delete", "retain"], "default": "delete", "description": "What deleting the record does with its record set: delete removes it (the record stays until that succeeds), retain leaves it in the zone"}
      }
    },
    "status": {
      "type": "object",
      "properties": {
        "zone":      {"type": "string"},
        "name":      {"type": "string"},
        "type":      {"type": "string"},
        "ttl":       {"type": "integer"},
        "values":    {"type": "array", "items": {"type": "string"}},
        "owned":     {"type": "boolean"},
        "writtenAt": {"type": "string"},
        "drifts":    {"type": "integer"},
        "lastDrift": {"type": "string"}
      }
    }
  }
}
EOT

  rule {
    expression = "has(self.spec.values) != has(self.spec.source)"
    message    = "a record takes its values from values or from source, one of them"
  }

  columns {
    column "Name" { path = "spec.name" }
    column "Type" { path = "spec.type" }
    column "Values" { path = "status.values" }
    column "Zone" { path = "status.zone" }
    column "Deletion" { path = "spec.deletion_policy" }
    column "Ready" { path = "status.conditions[?type=='Ready'].status" }
  }
}
[[- end ]]
