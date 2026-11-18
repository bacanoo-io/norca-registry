# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

module "placement" {
  source = "../lib/placement"

  datacenters = var.datacenters
  node_pool   = var.node_pool
  spread_over = ""
  node        = var.node
  constraints = var.constraints
}
