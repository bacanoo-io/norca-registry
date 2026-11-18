# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# HTTP-01 routed by another edge router, in a container.
driver             = "docker"
image              = "registry.example.com/norca/norca-acme:0.1.0"
http01_entrypoints = []
