[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
job [[ $v.job_name | quote ]] {
  type        = "service"
  namespace   = [[ $v.namespace | quote ]]
[[- if ne $v.region "" ]]
  region      = [[ $v.region | quote ]]
[[- end ]]
  datacenters = [[ $v.datacenters | toStringList ]]
  node_pool   = [[ $v.node_pool | quote ]]

  # Never on a node the operator created: such a node can be removed under
  # it, and an operator must not delete the machine it runs on.
  constraint {
    attribute = "${meta.norca.instance}"
    operator  = "is_not_set"
  }

  group "operator" {
    count = [[ $v.count ]]
[[- if gt (int $v.count) 1 ]]

    # The instances on different nodes: one node going does not take the
    # operator with it.
    constraint {
      operator = "distinct_hosts"
      value    = "true"
    }
[[- end ]]

    network {
      port "metrics" {}
    }

    task "operator" {
      driver = [[ $v.driver | quote ]]

      config {
[[- if eq $v.driver "mock_driver" ]]
        run_for = "87600h"
[[- else if eq $v.driver "docker" ]]
        image = [[ $v.image | quote ]]
        ports = ["metrics"]
        args  = [
[[- else ]]
        command = [[ $v.binary | quote ]]
        args = [
[[- end ]]
[[- if ne $v.driver "mock_driver" ]]
          "-log-level", [[ $v.log_level | quote ]],
          "-lease-namespace", [[ $v.namespace | quote ]],
          "-token-namespace", [[ $v.variables_namespace | quote ]],
          "-bootstrap-namespace", [[ $v.variables_namespace | quote ]],
          "-provider-ttl", [[ $v.provider_ttl | quote ]],
          "-provider-allow-http=[[ $v.provider_allow_http ]]",
          "-orphan-after", [[ $v.orphan_after | quote ]],
          "-resync", [[ $v.resync | quote ]],
[[- if eq $v.driver "docker" ]]
          # In the container the address of the host cannot be bound; the
          # port is mapped to the same port of the container.
          "-metrics-addr", ":${NORCA_PORT_metrics}",
[[- else ]]
          "-metrics-addr", "${NORCA_ADDR_metrics}",
[[- end ]]
        ]
[[- end ]]
      }

      # The operator calls the API on the task API socket with its workload
      # identity; the ACL policy of the pack is bound to this job. The region
      # comes from NORCA_REGION.
      identity {
        env = true
      }

      env {
        NORCA_ADDR = "unix://${NORCA_SECRETS_DIR}/api.sock"
      }

      resources {
        cpu    = [[ $v.cpu ]]
        memory = [[ $v.memory ]]
      }
    }
  }
}
