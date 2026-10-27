# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0
[[- $v := vars . ]]
[[- template "otel.validate" . ]]
[[- $job := $v.job_name ]][[ if eq $job "" ]][[ $job = (meta "pack.name" .) ]][[ end ]]
[[- $image := $v.image ]][[ if ne $v.image_digest "" ]][[ $image = printf "%s@%s" $v.image $v.image_digest ]][[ end ]]
[[- $identity := or (eq $v.openobserve_tls "mtls") (eq $v.postgres_tls "verify-ca") ]]
[[- $hostfs := and $v.hostmetrics_enabled (ne $v.host_root_volume "") ]]
[[- $serverName := $v.openobserve_server_name ]][[ if eq $serverName "" ]][[ $serverName = printf "%s.service.${NOMAD_NAMESPACE}.nomad" $v.openobserve_service ]][[ end ]]

# The OpenTelemetry Collector (contrib distribution, Apache-2.0), rendered by
# the otel-collector pack: one collector on every node, which collects the
# metrics of the node and of the platform components on it, receives OTLP
# from the applications of the node, and exports everything to OpenObserve.
job [[ $job | quote ]] {
  [[- if ne $v.region "" ]]
  region = [[ $v.region | quote ]]
  [[- end ]]
  [[- if ne $v.namespace "" ]]
  namespace = [[ $v.namespace | quote ]]
  [[- end ]]
  datacenters = [[ $v.datacenters | toStringList ]]
  [[- if ne $v.node_pool "" ]]
  node_pool = [[ $v.node_pool | quote ]]
  [[- end ]]
  type = "system"
  [[- range $c := $v.constraints ]]

  constraint {
    attribute = [[ $c.attribute | quote ]]
    operator  = [[ $c.operator | quote ]]
    [[- if ne $c.value "" ]]
    value = [[ $c.value | quote ]]
    [[- end ]]
  }
  [[- end ]]

  update {
    max_parallel     = 1
    min_healthy_time = "10s"
  }

  group "collector" {
    # Host networking (the task's network_mode): the host's network
    # interfaces for the host metrics, the local agent on 127.0.0.1, the OTLP
    # ports on the node address.
    network {
      [[- if $v.otlp_enabled ]]
      port "otlp_grpc" {
        static = [[ $v.otlp_grpc_port ]]
        [[- if ne $v.host_network "" ]]
        host_network = [[ $v.host_network | quote ]]
        [[- end ]]
      }

      port "otlp_http" {
        static = [[ $v.otlp_http_port ]]
        [[- if ne $v.host_network "" ]]
        host_network = [[ $v.host_network | quote ]]
        [[- end ]]
      }

      [[- end ]]
      port "health" {}
      [[- if $v.self_metrics_enabled ]]

      port "telemetry" {}
      [[- end ]]
    }
    [[- if $hostfs ]]

    # The host's root directory, read-only, for the host metrics.
    volume "hostfs" {
      type      = "host"
      source    = [[ $v.host_root_volume | quote ]]
      read_only = true
    }
    [[- end ]]

    secret_access {
      path = [[ $v.ingest_secret_path | quote ]]
    }
    [[- if $v.forgejo_metrics_enabled ]]

    secret_access {
      path = [[ $v.forgejo_metrics_secret_path | quote ]]
    }
    [[- end ]]
    [[- if $v.consul_metrics_enabled ]]

    secret_access {
      path = [[ $v.consul_metrics_secret_path | quote ]]
    }
    [[- end ]]
    [[- if $v.postgres_metrics_enabled ]]

    secret_access {
      path = [[ $v.postgres_secret_path | quote ]]
    }
    [[- end ]]
    [[- if ne $v.nomad_ca_secret_path "" ]]

    secret_access {
      path = [[ $v.nomad_ca_secret_path | quote ]]
    }
    [[- end ]]
    [[- if eq $v.openobserve_tls "secret" ]]

    secret_access {
      path = [[ $v.openobserve_ca_secret_path | quote ]]
    }
    [[- end ]]

    service {
      name     = [[ $job | quote ]]
      provider = "nomad"
      port     = "health"
      [[- if $identity ]]

      # The workload identity of the collector: a certificate and the trust
      # bundle of the region in secrets/mtls, with which it verifies
      # OpenObserve[[ if eq $v.postgres_tls "verify-ca" ]] and PostgreSQL[[ end ]]. The collector serves no TLS on this port.
      # It reads the bundle (ca_file) only when it loads its configuration:
      # the client reloads it (SIGHUP) when a new CA joins the bundle.
      mtls {
        mode          = "app"
        change_mode   = "signal"
        change_signal = "SIGHUP"
        change_on     = "bundle"
      }
      [[- end ]]

      check {
        name            = "startup"
        role            = "startup"
        type            = "http"
        path            = "/"
        interval        = "5s"
        timeout         = "2s"
        startup_timeout = "2m"
      }

      check {
        name     = "liveness"
        role     = "liveness"
        type     = "http"
        path     = "/"
        interval = "15s"
        timeout  = "3s"

        check_restart {
          limit = 3
          grace = "30s"
        }
      }
    }
    [[- if $v.otlp_enabled ]]

    # OTLP of the node for the applications (they send to the collector of
    # their own node: ${attr.unique.network.ip-address}:[[ $v.otlp_grpc_port ]]/[[ $v.otlp_http_port ]]).
    service {
      name     = "[[ $job ]]-otlp-grpc"
      provider = "nomad"
      port     = "otlp_grpc"
      tags     = ["otlp", "grpc"]
    }

    service {
      name     = "[[ $job ]]-otlp-http"
      provider = "nomad"
      port     = "otlp_http"
      tags     = ["otlp", "http"]
    }
    [[- end ]]

    task "collector" {
      driver = "docker"

      config {
        image        = [[ $image | quote ]]
        network_mode = "host"
        args         = ["--config", "/local/config.yaml"]
      }

      # secrets/nomad_token: the workload identity, with which the
      # Prometheus receiver reads the catalog (nomad_sd_configs).
      identity {
        file = true
      }
      [[- if $hostfs ]]

      volume_mount {
        volume           = "hostfs"
        destination      = "/hostfs"
        read_only        = true
        propagation_mode = "host-to-task"
      }
      [[- end ]]

      # The ingest credentials of OpenObserve, written by the bootstrap task
      # of the openobserve pack. The collector waits for them.
      secret "ingest" {
        path    = [[ $v.ingest_secret_path | quote ]]
        timeout = "15m"

        env {
          OO_USERNAME = "username"
          OO_PASSWORD = "password"
          [[- if eq $v.openobserve_organization "" ]]
          OO_ORG = "organization"
          [[- end ]]
        }
      }
      [[- if $v.forgejo_metrics_enabled ]]

      secret "forgejo" {
        path     = [[ $v.forgejo_metrics_secret_path | quote ]]
        optional = true
        timeout  = "10s"

        env {
          FORGEJO_METRICS_TOKEN = "token"
        }
      }
      [[- end ]]
      [[- if $v.consul_metrics_enabled ]]

      secret "consul" {
        path     = [[ $v.consul_metrics_secret_path | quote ]]
        optional = true
        timeout  = "10s"

        env {
          CONSUL_METRICS_TOKEN = "token"
        }
      }
      [[- end ]]
      [[- if $v.postgres_metrics_enabled ]]

      secret "postgres" {
        path     = [[ $v.postgres_secret_path | quote ]]
        optional = true
        timeout  = "10s"

        env {
          PG_MONITORING_PASSWORD = "password"
        }
      }
      [[- end ]]
      [[- if ne $v.nomad_ca_secret_path "" ]]

      template {
        data        = "{{ with nomadSecret \"[[ $v.nomad_ca_secret_path ]]\" }}{{ .ca }}{{ end }}"
        destination = "secrets/nomad-ca.pem"
        uid         = 10001
        gid         = 10001
        perms       = "0400"
        change_mode = "restart"
      }
      [[- end ]]
      [[- if eq $v.openobserve_tls "secret" ]]

      template {
        data        = "{{ with nomadSecret \"[[ $v.openobserve_ca_secret_path ]]\" }}{{ .ca }}{{ end }}"
        destination = "secrets/openobserve-ca.pem"
        uid         = 10001
        gid         = 10001
        perms       = "0400"
        change_mode = "restart"
      }
      [[- end ]]

      env {
        NODE_ID        = "${node.unique.id}"
        NODE_NAME      = "${node.unique.name}"
        OO_SERVER_NAME = [[ $serverName | quote ]]
        [[- if ne $v.openobserve_organization "" ]]
        OO_ORG = [[ $v.openobserve_organization | quote ]]
        [[- end ]]
      }

      # The configuration; a change (an instance of OpenObserve or PostgreSQL
      # moved) is applied with a reload (SIGHUP).
      template {
        destination   = "local/config.yaml"
        change_mode   = "signal"
        change_signal = "SIGHUP"
        data          = <<-EOF
[[ template "otel.config" . ]]
        EOF
      }

      kill_timeout = "20s"

      resources {
        cpu    = [[ $v.resources.cpu ]]
        memory = [[ $v.resources.memory ]]
      }
    }
  }
}
