# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0
[[- $v := vars . ]]
[[- template "oo.validate" . ]]
[[- $job := $v.job_name ]][[ if eq $job "" ]][[ $job = (meta "pack.name" .) ]][[ end ]]
[[- $mtls := eq $v.tls_mode "mtls" ]]
[[- $hn := $v.host_network ]]

# OpenObserve (AGPL-3.0, https://openobserve.ai), rendered by the openobserve
# pack: logs, metrics and traces of the cluster ([[ $v.mode ]] mode). The nodes pull the
# official image; Norca does not ship it.
job [[ $job | quote ]] {
  [[- template "oo.location" . ]]
  type = "service"
  [[- if eq $v.mode "single" ]]

  group "openobserve" {
    count = 1

    # A single instance with its data on one node: evictions are refused, and
    # a node drain moves it only when its deadline is reached.
    disruption {
      min_healthy = "1"
    }

    update {
      max_parallel      = 1
      health_check      = "checks"
      min_healthy_time  = "10s"
      healthy_deadline  = [[ $v.healthy_deadline | quote ]]
      progress_deadline = "0"
      auto_revert       = false
    }

    network {
      port "http" {
        static = [[ $v.http_port ]]
        to     = 5080
        [[- if ne $hn "" ]]
        host_network = [[ $hn | quote ]]
        [[- end ]]
      }

      port "grpc" {
        static = [[ $v.grpc_port ]]
        to     = 5081
        [[- if ne $hn "" ]]
        host_network = [[ $hn | quote ]]
        [[- end ]]
      }
    }

    volume "data" {
      type      = "host"
      source    = [[ $v.host_volume | quote ]]
      read_only = false
    }
    [[- template "oo.secret_access" (dict "ctx" . "bootstrap" $v.bootstrap_enabled) ]]

    # The UI, the API and OTLP/HTTP (/api/<organization>/v1/{logs,metrics,traces}).
    service {
      name     = [[ $job | quote ]]
      provider = "nomad"
      port     = "http"
      tags     = ["[[ if eq $v.tls_mode "none" ]]http[[ else ]]https[[ end ]]"]
      [[- if $mtls ]]

      # Norca's workload certificate (valid for [[ $job ]].service.<namespace>.nomad),
      # used by OpenObserve itself (app mode, no sidecar). OpenObserve reads it
      # only at start: the client restarts the task after a renewal or a CA
      # rotation (not counted against the restart policy).
      mtls {
        mode        = "app"
        change_mode = "restart"
      }
      [[- end ]]
      [[- template "oo.checks" . ]]
    }

    # OTLP/gRPC (headers organization and stream-name).
    service {
      name     = "[[ $job ]]-grpc"
      provider = "nomad"
      port     = "grpc"
      [[- if $mtls ]]

      mtls {
        mode        = "app"
        change_mode = "restart"
      }
      [[- end ]]
    }
    [[- template "oo.task" (dict "ctx" . "role" "all") ]]
    [[- template "oo.bootstrap" . ]]
  }
  [[- else ]]
  [[- range $role := list "router" "ingester" "querier" "compactor" "alertmanager" ]]
  [[- $r := get $v.roles $role ]]
  [[- $router := eq $role "router" ]]
  [[- $ingesterVolume := and (eq $role "ingester") (ne $v.ingester_host_volume "") ]]

  # Node role [[ $role ]] (ZO_NODE_ROLE).
  group [[ $role | quote ]] {
    count = [[ $r.count ]]
    [[- if $ingesterVolume ]]

    # One ingester per node: they keep their WAL in the host volume.
    constraint {
      operator = "distinct_hosts"
      value    = "true"
    }
    [[- end ]]

    # Drains and evictions take down one instance of the role at a time.
    disruption {
      max_unavailable = "1"
    }

    update {
      max_parallel      = 1
      health_check      = "checks"
      min_healthy_time  = "10s"
      healthy_deadline  = [[ $v.healthy_deadline | quote ]]
      progress_deadline = "0"
      auto_revert       = false
    }

    migrate {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "10s"
      healthy_deadline = [[ $v.healthy_deadline | quote ]]
    }
    [[- if not $ingesterVolume ]]

    # WAL (ingesters) and caches; the data itself is in S3.
    ephemeral_disk {
      sticky  = true
      migrate = [[ eq $role "ingester" ]]
      size    = [[ $v.cluster_disk_mb ]]
    }
    [[- else ]]

    volume "data" {
      type      = "host"
      source    = [[ $v.ingester_host_volume | quote ]]
      read_only = false
    }
    [[- end ]]

    # Host networking (the task's network_mode): [[ if $router ]]static ports for the users and
    # collectors[[ else ]]dynamic ports, advertised to the other nodes through NATS[[ end ]].
    network {
      port "http" {
        [[- if $router ]]
        static = [[ $v.http_port ]]
        [[- end ]]
        [[- if ne $hn "" ]]
        host_network = [[ $hn | quote ]]
        [[- end ]]
      }

      port "grpc" {
        [[- if $router ]]
        static = [[ $v.grpc_port ]]
        [[- end ]]
        [[- if ne $hn "" ]]
        host_network = [[ $hn | quote ]]
        [[- end ]]
      }
    }
    [[- template "oo.secret_access" (dict "ctx" $ "bootstrap" (and $router $v.bootstrap_enabled)) ]]

    service {
      name     = "[[ if $router ]][[ $job ]][[ else ]][[ $job ]]-[[ $role ]][[ end ]]"
      provider = "nomad"
      port     = "http"
      tags     = ["[[ $role ]]", "[[ if eq $v.tls_mode "none" ]]http[[ else ]]https[[ end ]]"]
      [[- if and $mtls $router ]]

      # Norca's workload certificate (valid for [[ $job ]].service.<namespace>.nomad).
      # OpenObserve reads it only at start: the client restarts the task after
      # a renewal or a CA rotation (not counted against the restart policy).
      mtls {
        mode        = "app"
        change_mode = "restart"
      }
      [[- end ]]
      [[- template "oo.checks" $ ]]
    }

    # gRPC of the node, registered by every role[[ if $mtls ]]: the workload certificates of all
    # nodes then carry [[ $job ]]-grpc.service.<namespace>.nomad, the name they verify
    # on internal calls (ZO_GRPC_TLS_CERT_DOMAIN)[[ end ]].
    service {
      name     = "[[ $job ]]-grpc"
      provider = "nomad"
      port     = "grpc"
      tags     = ["[[ $role ]]"]
      [[- if $mtls ]]

      mtls {
        mode        = "app"
        change_mode = "restart"
      }
      [[- end ]]
    }
    [[- template "oo.task" (dict "ctx" $ "role" $role) ]]
    [[- if $router ]]
    [[- template "oo.bootstrap" $ ]]
    [[- end ]]
  }
  [[- end ]]
  [[- end ]]
}
