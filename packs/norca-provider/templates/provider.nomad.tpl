[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
[[- $scheme := "http" ]][[ if $v.tls_enabled ]][[ $scheme = "https" ]][[ end ]]
[[- $advertise := printf "%s://${NORCA_IP_api}:%d" $scheme (int $v.port) ]][[ if ne $v.advertise_url "" ]][[ $advertise = $v.advertise_url ]][[ end ]]
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

  group "provider" {
    # One instance: the providers of the configuration are registered once,
    # and a platform that keeps its load balancers in the process (tcpproxy)
    # must not run twice.
    count = 1

    network {
      # The operators call the provider here: a static port, so the firewall
      # of the node can let them in.
      port "api" {
        static = [[ $v.port ]]
      }
    }

    service {
      name     = [[ $v.job_name | quote ]]
      port     = "api"
      provider = "nomad"

      check {
        type     = "http"
        protocol = [[ $scheme | quote ]]
        path     = "/healthz"
[[- if $v.tls_enabled ]]
        # The certificate may come from a CA the client does not know.
        tls_skip_verify = true
[[- end ]]
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "provider" {
      driver = [[ $v.driver | quote ]]

      config {
[[- if eq $v.driver "mock_driver" ]]
        run_for = "87600h"
[[- else if eq $v.driver "docker" ]]
        image = [[ $v.image | quote ]]
        ports = ["api"]
        args  = [
[[- else ]]
        command = [[ $v.binary | quote ]]
        args = [
[[- end ]]
[[- if ne $v.driver "mock_driver" ]]
          "-config", "${NORCA_TASK_DIR}/providers.json",
          "-log-level", [[ $v.log_level | quote ]],
          "-deregister-on-exit=[[ $v.deregister_on_exit ]]",
        ]
[[- end ]]
      }

      # The provider registers on the task API socket with its workload
      # identity; the ACL policy of the pack is bound to this job.
      identity {
        env = true
      }

      env {
        NORCA_ADDR = "unix://${NORCA_SECRETS_DIR}/api.sock"
      }
[[- if $v.secrets ]]

      # The items of the job's Variable as environment variables, for the
      # env:NAME references of the configuration (tokens, credentials).
      template {
        destination = "secrets/provider.env"
        env         = true
        change_mode = "restart"
        data        = <<-EOT
          {{- with nomadVar "nomad/jobs/[[ $v.job_name ]]" }}
          {{- range $k, $item := . }}
          {{ $k }}={{ $item.Value | toJSON }}
          {{- end }}
          {{- end }}
        EOT
      }
[[- end ]]
[[- if $v.tls_enabled ]]

      template {
        data        = "{{ with nomadVar \"nomad/jobs/[[ $v.job_name ]]\" }}{{ .tls_cert }}{{ end }}"
        destination = "secrets/tls.crt"
        change_mode = "restart"
      }

      template {
        data        = "{{ with nomadVar \"nomad/jobs/[[ $v.job_name ]]\" }}{{ .tls_key }}{{ end }}"
        destination = "secrets/tls.key"
        perms       = "0600"
        change_mode = "restart"
      }
[[- end ]]

      # The configuration of norca-provider. It expands $${NAME} with the
      # environment of the task when it starts; the dollar sign is doubled
      # here so that HCL leaves it alone.
      template {
        destination = "local/providers.json"
        change_mode = "restart"
        data        = <<EOT
{
  "listen": ":$${NORCA_PORT_api}",
[[- if $v.tls_enabled ]]
  "tls": { "cert": "$${NORCA_SECRETS_DIR}/tls.crt", "key": "$${NORCA_SECRETS_DIR}/tls.key" },
[[- end ]]
  "advertise_url": [[ replace "${" "$${" $advertise | quote ]],
  "heartbeat_interval": [[ $v.heartbeat_interval | quote ]],
  "providers": [[ replace "${" "$${" ($v.providers | trim) ]]
}
EOT
      }

      resources {
        cpu    = [[ $v.cpu ]]
        memory = [[ $v.memory ]]
      }
    }
  }
}
