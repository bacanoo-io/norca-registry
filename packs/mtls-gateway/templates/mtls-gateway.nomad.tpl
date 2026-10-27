# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0
[[- $v := vars . ]]
[[- template "gateway.validate" . ]]
[[- $system := eq $v.job_type "system" ]]
[[- $bridge := eq $v.network_mode "bridge" ]]
[[- $container := has $v.envoy_driver (list "docker" "podman") ]]

# The native mTLS gateway of a region, rendered by the mtls-gateway pack. It
# forwards TLS connections from other regions by their SNI name, without
# terminating them, to the mtls services of its region: mTLS stays end to end
# between the sidecars, and the intentions of the destination region decide.
job [[ $v.job_name | quote ]] {
  # Upstreams of other regions look for gateways in the default namespace.
  namespace = "default"
[[- if ne $v.region "" ]]
  region    = [[ $v.region | quote ]]
[[- end ]]
  datacenters = [[ $v.datacenters | toStringList ]]
[[- if ne $v.node_pool "" ]]
  node_pool   = [[ $v.node_pool | quote ]]
[[- end ]]
  type = [[ $v.job_type | quote ]]
[[- range $c := $v.constraints ]]

  constraint {
    attribute = [[ $c.attribute | quote ]]
    operator  = [[ $c.operator | quote ]]
[[- if ne $c.value "" ]]
    value     = [[ $c.value | quote ]]
[[- end ]]
  }
[[- end ]]

  update {
    max_parallel = [[ $v.update_max_parallel ]]
[[- if not $system ]]
    min_healthy_time = "10s"
[[- end ]]
  }

  group "gateway" {
    # The gateway port is static: the nodes of the other regions connect to
    # <node address>:[[ $v.port ]] (for example over the VPN between the clouds).
    network {
      mode = [[ $v.network_mode | quote ]]

      port "mtls" {
        static = [[ $v.port ]]
[[- if $bridge ]]
        to     = [[ $v.port ]]
[[- end ]]
[[- if ne $v.host_network "" ]]
        host_network = [[ $v.host_network | quote ]]
[[- end ]]
      }
[[- if $v.metrics_enabled ]]

      # The metrics listener of Envoy (/stats/prometheus only) and its admin
      # interface, which listens on 127.0.0.1 only.
      port "metrics" {
[[- if gt (int $v.metrics_port) 0 ]]
        static = [[ $v.metrics_port ]]
[[- end ]]
[[- if ne $v.host_network "" ]]
        host_network = [[ $v.host_network | quote ]]
[[- end ]]
      }

      port "envoy_admin" {}
[[- end ]]
    }
[[- if not $system ]]

    count = [[ $v.count ]]
[[- if $v.distinct_hosts ]]

    # The instances share the static port: one per node.
    constraint {
      operator = "distinct_hosts"
      value    = "true"
    }
[[- end ]]
[[- end ]]

    # The servers inject the Envoy task mtls-gateway-<service> of kind
    # mtls-gateway:<service> unless the group defines one (envoy_task_enabled).
    service {
      name     = [[ $v.service_name | quote ]]
      port     = "mtls"
      provider = "nomad"
[[- if $v.service_tags ]]
      tags     = [[ $v.service_tags | toStringList ]]
[[- end ]]

      mtls {
        mode = "gateway"
      }
    }
[[- if $v.metrics_enabled ]]

    # The statistics of the gateway for the otel-collector pack. No checks:
    # the gateway's health doesn't depend on its metrics.
    service {
      name     = "[[ $v.service_name ]]-metrics"
      port     = "metrics"
      provider = "nomad"
      tags     = ["metrics"]
    }
[[- end ]]
[[- if $v.envoy_task_enabled ]]

    # The Envoy task, defined by the pack instead of injected by the servers.
    # The client writes its configuration (${NOMAD_SECRETS_DIR}/envoy) and
    # replaces the node meta references of the image and the log level.
    task "envoy" {
      kind   = "mtls-gateway:[[ $v.service_name ]]"
      driver = [[ $v.envoy_driver | quote ]]

      config {
[[- if $container ]]
[[- if ne $v.envoy_image "" ]]
        image = [[ $v.envoy_image | quote ]]
[[- else ]]
        image = "${meta.norca.mtls.envoy_image}"
[[- end ]]
        args  = [[ template "gateway.envoy_args" . ]]
[[- if not $bridge ]]
        network_mode = "host"
[[- end ]]
[[- else ]]
        command = [[ $v.envoy_binary | quote ]]
        args    = [[ template "gateway.envoy_args" . ]]
[[- end ]]
      }

      # Only Norca clients write the Envoy configuration.
      constraint {
        attribute = "${attr.norca.version}"
        operator  = "is_set"
      }

      shutdown_delay = "5s"

      logs {
        max_files     = 2
        max_file_size = 2
      }

      resources {
        cpu    = [[ $v.envoy_resources.cpu ]]
        memory = [[ $v.envoy_resources.memory ]]
      }
    }
[[- end ]]
  }
}
