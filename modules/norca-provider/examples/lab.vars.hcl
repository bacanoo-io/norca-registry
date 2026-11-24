# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# A lab: the docker platform (each node a container on the host of the
# provider) and a mock class, on http (the token travels in the clear, never
# in production). raw_exec, as the docker platform needs the docker CLI of
# its host: the lab gives up the isolation of the operators from raw_exec
# nodes (allow_raw_exec_nodes, review finding JOG-19). The address of the
# task is the address of the host the containers' traffic leaves from: the
# default of host_addresses.
#   norca var put -namespace norca-system nomad/jobs/norca-provider LAB_TOKEN=...
#   norca var put -namespace norca-system nodescaler/providers/lab token=...
#   rigger install ./modules/norca-provider -name norca-provider -namespace norca-system -f modules/norca-provider/examples/lab.vars.hcl
driver               = "raw_exec"
allow_raw_exec_nodes = true
port                 = 8480
log_level            = "debug"
secrets              = true
providers            = <<EOT
[
  {
    "name": "lab",
    "type": "docker",
    "token": "env:LAB_TOKEN",
    "token_variable": "nodescaler/providers/lab",
    "node": {
      "params": { "state_dir": "/var/lib/norca-provider" },
      "groups": [ { "name": "dc2", "max": 3, "params": { "cpu": 2000, "memory": 1024, "disk": 10000 } } ]
    }
  },
  {
    "name": "lab-mock",
    "type": "mock",
    "token": "env:LAB_TOKEN",
    "token_variable": "nodescaler/providers/lab",
    "loadbalancer": { "classes": [ { "class": "lab-mock", "params": { "address": "$${NORCA_IP_api}" } } ] }
  }
]
EOT
