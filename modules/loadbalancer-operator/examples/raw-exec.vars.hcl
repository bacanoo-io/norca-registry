# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# A lab or a single-tenant cluster whose nodes run with the raw_exec driver
# (a dev agent): the controller runs with raw_exec too and gives up its
# isolation from raw_exec work (allow_raw_exec_nodes, review finding
# JOG-19), and the proxy jobs use raw_exec as well. Without
# allow_raw_exec_nodes the module refuses driver = "raw_exec".
driver               = "raw_exec"
allow_raw_exec_nodes = true
proxy_driver         = "raw_exec"
