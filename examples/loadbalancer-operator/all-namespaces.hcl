# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# One controller for the load balancers of every namespace, running in the
# operations namespace norca-system (the default of namespace): outside the
# quota of the teams, and not a job a team token can touch.
#   norca pack run loadbalancer-operator --registry=norca -f examples/loadbalancer-operator/all-namespaces.hcl
watch_namespace = "*"
