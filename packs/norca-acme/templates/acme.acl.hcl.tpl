[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
[[- $tokens := $v.zone_token_namespace ]][[ if eq $tokens "" ]][[ $tokens = $v.namespace ]][[ end ]]
[[- if $v.acl_policy_enabled ]]
policy [[ printf "%s" $v.job_name | quote ]] {
  description = "Permissions of norca-acme (bound to its job)"
  rules       = <<EOT
# The kinds are cluster-scoped: their rules are in the namespace "*". The
# operator reads the issuers and the orders the servers write, writes the
# status of the issuers that name it and of their orders, and reads the DNS
# zones norca-provider registers. It reads no secret of any other path: the
# keys of the certificates stay with the servers.
namespace "*" {
  object "norca.io/CertificateIssuer" {
    capabilities = ["read", "write-status"]
  }

  object "norca.io/CertificateOrder" {
    capabilities = ["read", "write-status"]
  }

  object "norca.io/DNSZone" {
    capabilities = ["read"]
  }
}

# The secrets of the operator: the keys of its accounts, the certificates
# it issued (for a revocation), an external account binding.
namespace "[[ $v.namespace ]]" {
  secret "[[ $v.secret_prefix ]]*" {
    capabilities = ["read-secret", "write-secret"]
  }
[[- if eq $tokens $v.namespace ]]

  # The tokens of the DNS zones.
  variables {
    path [[ $v.zone_token_path | quote ]] {
      capabilities = ["read"]
    }
  }
[[- end ]]
}
[[- if ne $tokens $v.namespace ]]

# The tokens of the DNS zones.
namespace "[[ $tokens ]]" {
  variables {
    path [[ $v.zone_token_path | quote ]] {
      capabilities = ["read"]
    }
  }
}
[[- end ]]
EOT

  job_acl {
    namespace = [[ $v.namespace | quote ]]
    job_id    = [[ $v.job_name | quote ]]
  }
}
[[- end ]]
