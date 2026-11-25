# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# A lab with a name server that takes dynamic updates, served by
# norca-provider over http: the operator accepts the http endpoint and
# compares the records with the zone every 20 seconds.
#
#   norca rigger install ./modules/norca-dns -name norca-dns -namespace norca-system -f modules/norca-dns/examples/lab.vars.hcl
log_level       = "debug"
requeue         = "20s"
zone_allow_http = true
