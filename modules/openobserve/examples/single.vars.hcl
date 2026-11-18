# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

resources = {
  cpu    = 2000
  memory = 4096
}

extra_env = {
  ZO_COMPACT_DATA_RETENTION_DAYS = "30"
}
