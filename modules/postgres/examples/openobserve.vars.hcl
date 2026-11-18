# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

databases = [
  {
    name        = "openobserve"
    user        = "openobserve"
    secret_path = "postgres/openobserve"
  },
]

settings = {
  max_connections = "200"
  shared_buffers  = "256MB"
}
