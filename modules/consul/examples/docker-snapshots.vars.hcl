# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Docker from a mirror with a pinned digest, snapshots with credentials
# and path-style addressing.
image_registry     = "registry.example.com"
image_tag          = "2.1"
image_digest       = "sha256:5555555555555555555555555555555555555555555555555555555555555555"
snapshot_enabled   = true
snapshot_s3_bucket = "norca-backup"

# The installer's acceptance of the Consul license (BSL 1.1): read it first.
consul_license_accepted = true
