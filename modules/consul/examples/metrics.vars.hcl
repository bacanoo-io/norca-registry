# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Three Consul servers and the client agents with the agent metrics for the
# otel-collector module (service consul-metrics, token from the secret
# consul/metrics). Consul is BSL 1.1: accept its license at install.
#   cat /proc/sys/kernel/random/uuid | norca secret put consul/metrics token=-
#   norca rigger install ./modules/consul -name consul -f modules/consul/examples/metrics.vars.hcl
metrics_enabled = true

# The installer's acceptance of the Consul license (BSL 1.1): read it first.
consul_license_accepted = true
