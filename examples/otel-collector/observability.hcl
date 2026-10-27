# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The collectors of the observability namespace: Norca agents with TLS
# (the CA of the agent certificates in the secret norca/agent-ca), the
# metrics services of the namespaces default and observability, PostgreSQL
# of the postgres pack in this namespace.
#   norca secret put -namespace observability norca/agent-ca ca=@nomad-agent-ca.pem
#   norca pack run otel-collector --registry=norca -f examples/otel-collector/observability.hcl
namespace            = "observability"
nomad_address        = "https://127.0.0.1:4646"
nomad_ca_secret_path = "norca/agent-ca"
discovery_namespaces = ["default", "observability"]
