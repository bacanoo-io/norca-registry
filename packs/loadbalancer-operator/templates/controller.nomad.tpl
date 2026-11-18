[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
[[- $watch := $v.namespace ]]
[[- if ne $v.watch_namespace "" ]][[ $watch = $v.watch_namespace ]][[ end ]]
[[- $tokens := $v.class_token_namespace ]][[ if eq $tokens "" ]][[ $tokens = $v.namespace ]][[ end ]]
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

  group "controller" {
    count = [[ $v.count ]]

    network {
      port "metrics" {}
[[- if $v.webhook_enabled ]]
      port "webhook" {
        static = [[ $v.webhook_port ]]
      }
[[- end ]]
    }

    task "controller" {
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
          "controller",
          "-objects", "native",
          "-namespace", [[ $watch | quote ]],
          "-lease-namespace", [[ $v.namespace | quote ]],
          "-log-level", [[ $v.log_level | quote ]],
          "-discover-services=[[ $v.discover_services ]]",
          "-proxy-driver", [[ $v.proxy_driver | quote ]],
[[- if eq $v.proxy_driver "docker" ]]
          "-proxy-image", [[ $v.proxy_image | quote ]],
[[- else if ne $v.proxy_driver "mock_driver" ]]
          "-proxy-command", [[ $v.binary | quote ]],
[[- end ]]
          "-metrics-addr", "${NORCA_ADDR_metrics}",
          "-class-ttl", [[ $v.class_ttl | quote ]],
          "-class-token-namespace", [[ $tokens | quote ]],
          "-class-allow-http=[[ $v.class_allow_http ]]",
[[- if ne $v.class_ca_cert "" ]]
          "-class-ca-file", "${NORCA_TASK_DIR}/class-ca.pem",
[[- end ]]
        ]
[[- end ]]
      }
[[- if and (ne $v.class_ca_cert "") (ne $v.driver "mock_driver") ]]

      # The CA of the providers' https certificates.
      template {
        data        = <<EOT
[[ $v.class_ca_cert | trim ]]
EOT
        destination = "local/class-ca.pem"
        change_mode = "restart"
      }
[[- end ]]

      # The controller calls the API on the task API socket with its
      # workload identity; the ACL policy of the pack is bound to this job.
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
[[- if $v.webhook_enabled ]]

    # The defaulting and validating webhooks of the LoadBalancer kind. The
    # certificate and key come from the job's Variable (nomad/jobs/<job>,
    # items webhook_cert and webhook_key).
    task "webhook" {
      driver = [[ $v.driver | quote ]]

      config {
[[- if eq $v.driver "mock_driver" ]]
        run_for = "87600h"
[[- else if eq $v.driver "docker" ]]
        image = [[ $v.image | quote ]]
        ports = ["webhook"]
        args  = [
[[- else ]]
        command = [[ $v.binary | quote ]]
        args = [
[[- end ]]
[[- if ne $v.driver "mock_driver" ]]
          "webhook",
          "-listen", ":${NORCA_PORT_webhook}",
          "-tls-cert", "${NORCA_SECRETS_DIR}/webhook.pem",
          "-tls-key", "${NORCA_SECRETS_DIR}/webhook-key.pem",
          "-classes", [[ join "," $v.classes | quote ]],
          "-default-class", [[ $v.default_class | quote ]],
        ]
[[- end ]]
      }
[[- if ne $v.driver "mock_driver" ]]

      template {
        data        = "{{ with nomadVar \"nomad/jobs/[[ $v.job_name ]]\" }}{{ .webhook_cert }}{{ end }}"
        destination = "secrets/webhook.pem"
        change_mode = "restart"
      }

      template {
        data        = "{{ with nomadVar \"nomad/jobs/[[ $v.job_name ]]\" }}{{ .webhook_key }}{{ end }}"
        destination = "secrets/webhook-key.pem"
        change_mode = "restart"
      }
[[- end ]]

      service {
        name     = "[[ $v.job_name ]]-webhook"
        port     = "webhook"
        provider = "nomad"
      }

      resources {
        cpu    = 50
        memory = 32
      }
    }
[[- end ]]
  }
}
