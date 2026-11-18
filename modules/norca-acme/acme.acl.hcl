# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The permissions of norca-acme, bound to its job.
policy "acme" {
  enabled = var.acl_policy_enabled

  name        = var.job_name
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
namespace "${rig.namespace}" {
  secret "${var.secret_prefix}*" {
    capabilities = ["read-secret", "write-secret"]
  }
%{~if local.tokens_here}

  # The tokens of the DNS zones.
  variables {
    path ${jsonencode(var.zone_token_path)} {
      capabilities = ["read"]
    }
  }
%{~endif}
}
%{~if !local.tokens_here}

# The tokens of the DNS zones.
namespace "${var.zone_token_namespace}" {
  variables {
    path ${jsonencode(var.zone_token_path)} {
      capabilities = ["read"]
    }
  }
}
%{~endif}
EOT

  job_acl {
    namespace = rig.namespace
    job_id    = var.job_name
  }
}
