[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
[[- $tokens := $v.zone_token_namespace ]][[ if eq $tokens "" ]][[ $tokens = $v.namespace ]][[ end ]]
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

  group "acme" {
    # One instance: the answers of the HTTP-01 challenges are in the memory
    # of the instance that placed the order, and the edge router would send
    # a challenge to any instance. An order that is open when the instance
    # is lost is continued by the next one, from the status of the order.
    count = 1
[[- if $v.http01_enabled ]]

    network {
      port "http01" {}
    }

    # The HTTP-01 challenge. The tags are a router of the Traefik pack
    # (acme_challenge = true there): the path of the challenge of every
    # host, on the http entrypoints, to this service.
    service {
      name     = [[ $v.job_name | quote ]]
      port     = "http01"
      provider = "nomad"
[[- if gt (len $v.http01_entrypoints) 0 ]]
      tags = [
        "traefik.enable=true",
        [[ printf "traefik.http.routers.%s.rule=PathPrefix(`/.well-known/acme-challenge/`)" $v.job_name | quote ]],
        [[ printf "traefik.http.routers.%s.entrypoints=%s" $v.job_name (join "," $v.http01_entrypoints) | quote ]],
        [[ printf "traefik.http.routers.%s.priority=2147483000" $v.job_name | quote ]],
      ]
[[- end ]]

      check {
        type     = "http"
        path     = "/healthz"
        interval = "10s"
        timeout  = "2s"
      }
    }
[[- end ]]

    task "acme" {
      driver = [[ $v.driver | quote ]]

      config {
[[- if eq $v.driver "mock_driver" ]]
        run_for = "87600h"
[[- else if eq $v.driver "docker" ]]
        image = [[ $v.image | quote ]]
[[- if $v.http01_enabled ]]
        ports = ["http01"]
[[- end ]]
        args  = [
[[- else ]]
        command = [[ $v.binary | quote ]]
        args = [
[[- end ]]
[[- if ne $v.driver "mock_driver" ]]
          "-controller", [[ $v.controller | quote ]],
          "-interval", [[ $v.interval | quote ]],
[[- if $v.http01_enabled ]]
          "-http01-listen", ":${NORCA_PORT_http01}",
[[- else ]]
          "-http01-listen", "",
[[- end ]]
          "-secret-namespace", [[ $v.namespace | quote ]],
          "-secret-prefix", [[ $v.secret_prefix | quote ]],
          "-zone-token-namespace", [[ $tokens | quote ]],
          "-zone-ttl", [[ $v.zone_ttl | quote ]],
          "-zone-allow-http=[[ $v.zone_allow_http ]]",
[[- if ne $v.zone_ca_cert "" ]]
          "-zone-ca-file", "${NORCA_TASK_DIR}/zone-ca.pem",
[[- end ]]
[[- if ne $v.dns_resolver "" ]]
          "-dns-resolver", [[ $v.dns_resolver | quote ]],
[[- end ]]
          "-dns-propagation-check=[[ $v.dns_propagation_check ]]",
          "-dns-propagation-timeout", [[ $v.dns_propagation_timeout | quote ]],
[[- if ne $v.acme_ca_cert "" ]]
          "-acme-ca-file", "${NORCA_TASK_DIR}/acme-ca.pem",
[[- end ]]
          "-retry-base", [[ $v.retry_base | quote ]],
          "-retry-max", [[ $v.retry_max | quote ]],
          "-max-attempts", [[ printf "%v" $v.max_attempts | quote ]],
          "-log-level", [[ $v.log_level | quote ]],
        ]
[[- end ]]
      }
[[- if and (ne $v.acme_ca_cert "") (ne $v.driver "mock_driver") ]]

      # The CA of the https certificate of the ACME directory.
      template {
        data        = <<EOT
[[ $v.acme_ca_cert | trim ]]
EOT
        destination = "local/acme-ca.pem"
        change_mode = "restart"
      }
[[- end ]]
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
