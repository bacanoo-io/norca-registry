# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Two instances on different nodes, with leader election (review finding
# CON-6e): one of them writes the records, the other takes over within the
# lease when it is lost. More than one instance turns leader election on,
# and the ACL policy of the module grants the lease, the Variable
# controller-lease/norca-dns in the namespace of the job.
#
count = 2
