# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The catalog of several namespaces over the HTTP API, every service
# exposed, one certificate as the default.
catalog_namespaces = ["default", "shop"]
exposed_by_default = true
nomad_address      = "https://127.0.0.1:4646"
tls_certificates   = ["certs/shop"]
