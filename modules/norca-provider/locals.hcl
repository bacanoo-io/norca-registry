# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

locals {
  mock   = var.driver == "mock_driver"
  docker = var.driver == "docker"
  scheme = var.tls_enabled ? "https" : "http"

  # Where the operators call the provider: the address of the allocation,
  # filled in by the provider when it starts.
  advertise = var.advertise_url != "" ? var.advertise_url : "${local.scheme}://$${NORCA_IP_api}:${var.port}"

  variable_path = "nomad/jobs/${var.job_name}"
}
