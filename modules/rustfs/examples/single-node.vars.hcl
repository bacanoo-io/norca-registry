# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# One RustFS server as the backup store of a single Norca node, with the
# backup bucket created by the module and the console enabled.
#   norca secret put rustfs/root access_key=norca-backup secret_key=-
#   norca rigger install ./modules/rustfs -name rustfs -f modules/rustfs/examples/single-node.vars.hcl
buckets         = ["norca-backup"]
console_enabled = true
