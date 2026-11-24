# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# One controller for the load balancers of every namespace, running in the
# operations namespace norca-system (the namespace of the release): outside
# the quota of the teams, and not a job a team token can touch.
#   rigger install ./modules/loadbalancer-operator -name lb -namespace norca-system -f modules/loadbalancer-operator/examples/all-namespaces.vars.hcl
watch_namespace = "*"
