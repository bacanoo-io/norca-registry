# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

mode    = "distributed"
nodes   = ["10.0.1.11", "10.0.1.12", "10.0.1.13", "10.0.1.14"]
buckets = ["norca-backup"]

constraints = [
  {
    attribute = "$${meta.storage}"
    operator  = "="
    value     = "s3"
  },
]

resources = {
  cpu    = 1000
  memory = 2048
}
