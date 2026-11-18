[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
[[- $tokens := $v.zone_token_namespace ]][[ if eq $tokens "" ]][[ $tokens = $v.namespace ]][[ end ]]
[[- if and (eq $v.driver "raw_exec") (not $v.allow_raw_exec_nodes) ]]
[[- fail `driver = "raw_exec" needs allow_raw_exec_nodes = true, as the job would then run on a node with the raw_exec driver, where a raw_exec task or alloc-node-exec reads its identity token (review finding JOG-19). Use driver = "exec" or "docker", or set allow_raw_exec_nodes = true knowingly` -]]
[[- end ]]
job [[ $v.job_name | quote ]] {
  type        = "service"
  namespace   = [[ $v.namespace | quote ]]
[[- if ne $v.region "" ]]
  region      = [[ $v.region | quote ]]
[[- end ]]
  datacenters = [[ $v.datacenters | toStringList ]]
  node_pool   = [[ $v.node_pool | quote ]]

  # Never on a node the node scaling operator created: such a node can be
  # removed under it.
  constraint {
    attribute = "${meta.norca.instance}"
    operator  = "is_not_set"
  }
[[- if not $v.allow_raw_exec_nodes ]]

  # Never on a node with the raw_exec driver (review finding JOG-19): a
  # raw_exec task or alloc-node-exec there runs as the user of the agent and
  # reads the secrets of every allocation of the node, the identity token of
  # this job and its bound ACL policies among them (allow_raw_exec_nodes).
  constraint {
    attribute = "${attr.driver.raw_exec}"
    operator  = "is_not_set"
  }
[[- end ]]

  group "dns" {
    # One instance: a record is written by one writer at a time; a record
    # that changes while the instance is away is reconciled by the next one.
    count = 1

    task "dns" {
      driver = [[ $v.driver | quote ]]

      config {
[[- if eq $v.driver "mock_driver" ]]
        run_for = "87600h"
[[- else if eq $v.driver "docker" ]]
        image = [[ $v.image | quote ]]
        args  = [
[[- else ]]
        command = [[ $v.binary | quote ]]
        args = [
[[- end ]]
[[- if ne $v.driver "mock_driver" ]]
          "-requeue", [[ $v.requeue | quote ]],
          "-zone-token-namespace", [[ $tokens | quote ]],
          "-zone-ttl", [[ $v.zone_ttl | quote ]],
          "-zone-allow-http=[[ $v.zone_allow_http ]]",
[[- if ne $v.zone_ca_cert "" ]]
          "-zone-ca-file", "${NORCA_TASK_DIR}/zone-ca.pem",
[[- end ]]
          "-log-level", [[ $v.log_level | quote ]],
        ]
[[- end ]]
      }
[[- if and (ne $v.zone_ca_cert "") (ne $v.driver "mock_driver") ]]

      # The CA of the https certificates of the DNS providers.
      template {
        data        = <<EOT
[[ $v.zone_ca_cert | trim ]]
EOT
        destination = "local/zone-ca.pem"
        change_mode = "restart"
      }
[[- end ]]

      # The operator calls the API on the task API socket with its workload
      # identity; the ACL policy of the pack is bound to this job.
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
