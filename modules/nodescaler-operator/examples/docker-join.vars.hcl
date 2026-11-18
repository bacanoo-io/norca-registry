# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The operator in containers with the join endpoint and orphans deleted.
driver         = "docker"
image          = "registry.example.com/norca-nodescaler:0.10.0"
join_enabled   = true
join_urls      = ["https://a.example.com:8490", "https://b.example.com:8490"]
delete_orphans = true
