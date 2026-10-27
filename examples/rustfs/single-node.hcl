# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# One RustFS server as the backup store of a single Norca node, with the
# backup bucket created by the pack and the console enabled.
#   norca secret put rustfs/root access_key=norca-backup secret_key=-
#   norca pack run rustfs --registry=norca -f examples/rustfs/single-node.hcl
buckets         = ["norca-backup"]
console_enabled = true
