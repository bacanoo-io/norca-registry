# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

mode = "cluster"

roles = {
  router       = { count = 2, cpu = 500, memory = 1024 }
  ingester     = { count = 3, cpu = 2000, memory = 4096 }
  querier      = { count = 2, cpu = 2000, memory = 4096 }
  compactor    = { count = 1, cpu = 1000, memory = 2048 }
  alertmanager = { count = 1, cpu = 250, memory = 512 }
}
