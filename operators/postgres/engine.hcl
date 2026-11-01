# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# norca secret engine apply -namespace apps engine.hcl
name        = "postgres"
type        = "operator"
description = "Orders database"

operator {
  service = "postgres-operator"
}

role "app" {
  ttl     = "1h"
  max_ttl = "24h"

  # The rights come from the group roles; see the README for the setup.
  config = {
    member_of = "orders_rw"
    sslmode   = "require"
  }
}
