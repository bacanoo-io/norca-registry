# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

module {
  name        = "rustfs"
  version     = "0.2.0"
  description = "RustFS (Apache-2.0), an S3-compatible object store, as the backup store of Norca: single node or distributed, credentials from the built-in secret store, data on host volumes, health checks with roles, optional bucket creation."
  url         = "https://rustfs.com"

  requires {
    norca = ">= 0.1.0"
  }
}
