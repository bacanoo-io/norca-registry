# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# HTTPS on another port, S3 over TLS at a fixed endpoint with a daily dump,
# metrics without a token, no admin task, a host network and a pinned
# image.
https_enabled             = true
http_port                 = 8443
ssh_port                  = 2022
host_network              = "private"
storage_endpoint          = "s3.example.com:443"
storage_use_ssl           = true
dump_enabled              = true
dump_prefix               = "nightly/"
metrics_enabled           = true
metrics_token_secret_path = ""
admin_enabled             = false
image_digest              = "sha256:1111111111111111111111111111111111111111111111111111111111111111"
require_signin_view       = true
