# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

locals {
  # The ID of the job and the prefix of its services; empty is the release.
  job = coalesce(var.job_name, rigger.release)
}
