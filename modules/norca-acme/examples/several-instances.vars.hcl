# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Two instances on different nodes, with leader election (review findings
# CON-6e, CON-6f, CON-6g): one of them works on the orders and answers the
# HTTP-01 challenges, the other takes over within the lease when it is
# lost. More than one instance turns leader election on, the ACL policy of
# the module grants the lease (the Variable controller-lease/norca-acme in
# the namespace of the job), and the service gets a check on /readyz that
# only the instance that leads passes.
#
# The cluster must route the challenges to the healthy instance only: the
# clients that run Traefik need
#
#   client {
#     native_service_discovery {
#       default_healthy_only = true
#     }
#   }
#
count = 2

# The settle time of the operator, written out: the check on /readyz (5s
# and its timeout of 2s), the second the client takes to pass the result on,
# and the refresh of Traefik (15s, applied 2s later) are 25s. Raise it with
# a slower refresh of the edge router.
http01_settle = "30s"
