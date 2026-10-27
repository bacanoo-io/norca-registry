# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Three Consul servers and the client agents with the agent metrics for the
# otel-collector pack (service consul-metrics, token from the secret
# consul/metrics). Consul is BSL 1.1: accept its license at install.
#   cat /proc/sys/kernel/random/uuid | norca secret put consul/metrics token=-
#   norca pack run consul --registry=norca --var consul_license_accepted=true -f examples/consul/metrics.hcl
metrics_enabled = true
