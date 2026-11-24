# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# A lab or a single-tenant cluster whose nodes run with the raw_exec driver:
# the operator runs with raw_exec too and gives up its isolation from
# raw_exec work (allow_raw_exec_nodes, review finding JOG-19). Without
# allow_raw_exec_nodes the module refuses driver = "raw_exec".
driver               = "raw_exec"
allow_raw_exec_nodes = true
