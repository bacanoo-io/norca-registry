# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Three NATS servers with token authentication: the token is the item
# client_token of the Variable nomad/jobs/nats (plain, or a bcrypt hash made
# with nats server passwd). Any characters are allowed in the token.
#   norca var put nomad/jobs/nats client_token=-
#   norca rigger install ./modules/nats -name nats -f modules/nats/examples/token.vars.hcl
auth_mode = "token"
