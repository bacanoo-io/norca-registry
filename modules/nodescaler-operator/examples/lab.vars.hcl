# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# A lab: one instance from an image, in the system pool, providers on http
# (the token of a provider travels in the clear, never in production).
# The image is yours: the norca-nodescaler binary as its entrypoint.
#   norca pack run nodescaler-operator --registry=norca -f examples/nodescaler-operator/lab.hcl
#   norca object get norca.io/NodeGroup workers-dc-a
node_pool           = "system"
count               = 1
driver              = "docker"
image               = "registry.example.com/norca-nodescaler:0.1.0"
log_level           = "debug"
variables_namespace = "ops"
provider_allow_http = true
orphan_after        = "5m"
resync              = "30s"
