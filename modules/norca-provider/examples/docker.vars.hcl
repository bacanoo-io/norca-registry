# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The provider in a container, in one datacenter of a lab, with TLS and no
# policy or kind of its own.
driver                  = "docker"
image                   = "registry.example.com/norca/norca-provider:0.4.0"
datacenters             = ["dc1"]
allow_single_datacenter = true
tls_enabled             = true
deregister_on_exit      = false
zone_kind_enabled       = false
acl_policy_enabled      = false
