# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

app {
  url = "https://forgejo.org"
}

pack {
  name        = "forgejo"
  description = "Forgejo (GPL-3.0-or-later, referenced, never shipped) as the internal git server and container (OCI) registry of a Norca cluster: SQLite and the repositories on a host volume, packages, LFS and attachments in RustFS, secrets from the built-in secret store, optional HTTPS, SSH, initial admin and periodic dumps."
  version     = "0.2.0"

  requires {
    norca = ">= 0.1.0"
  }
}
