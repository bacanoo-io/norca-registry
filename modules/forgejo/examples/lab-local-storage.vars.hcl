# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# A lab: everything on the host volume (no S3), plain HTTP on port 3000.
# Pushing and pulling images then needs the insecure-registries setting of
# the Docker daemons (labs only, see the README).
#   norca pack run forgejo --registry=norca --name=forgejo -f examples/forgejo/lab-local-storage.hcl
storage_enabled = false
admin_enabled   = true
