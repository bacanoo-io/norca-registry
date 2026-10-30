# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0
[[- $v := vars . ]]
[[- template "traefik.validate" . ]]
[[- $job := $v.job_name ]][[ if eq $job "" ]][[ $job = (meta "pack.name" .) ]][[ end ]]
[[- $image := $v.image ]][[ if ne $v.image_digest "" ]][[ $image = printf "%s@%s" $v.image $v.image_digest ]][[ end ]]
[[- $host := eq $v.network_mode "host" ]]
[[- $certs := $v.tls_certificates ]]
[[- $default := $v.tls_default_certificate ]][[ if and (eq $default "") (gt (len $certs) 0) ]][[ $default = index $certs 0 ]][[ end ]]
[[- $labels := list "admin" ]][[ range $e := $v.entrypoints ]][[ $labels = append $labels (printf "ep_%s" (replace "-" "_" $e.name)) ]][[ end ]]

# Traefik Proxy (MIT), rendered by the traefik pack: the edge router of the
# region. The entrypoints are the ports open to the outside; the routes come
# from the tags of the services in Norca's native catalog (Nomad provider)
# and from the static routes of the pack (file provider), the certificates
# from the secret store.
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
  type = [[ $v.job_type | quote ]]
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
    healthy_deadline = "3m"
    auto_revert      = true
  }

  group "traefik" {
    [[- if eq $v.job_type "service" ]]
    count = [[ $v.count ]]

    # One instance per node: the entrypoints are static ports.
    constraint {
      operator = "distinct_hosts"
      value    = "true"
    }
    [[- end ]]

    network {
      [[- if not $host ]]
      mode = "bridge"
      [[- end ]]

      # The admin entrypoint (/ping, dashboard, metrics) on the default
      # network of the node, never on host_network.
      port "admin" {
        static = [[ $v.admin_port ]]
        [[- if not $host ]]
        to = [[ $v.admin_port ]]
        [[- end ]]
      }
      [[- range $e := $v.entrypoints ]]

      port [[ printf "ep_%s" (replace "-" "_" $e.name) | quote ]] {
        static = [[ $e.port ]]
        [[- if not $host ]]
        to = [[ $e.port ]]
        [[- end ]]
        [[- if ne $v.host_network "" ]]
        host_network = [[ $v.host_network | quote ]]
        [[- end ]]
      }
      [[- end ]]
    }

    [[- $secrets := $certs ]][[ if and (ne $default "") (not (has $default $certs)) ]][[ $secrets = append $certs $default ]][[ end ]]
    [[- range $p := $secrets ]]

    # The certificate secret, read by the TLS template with the workload
    # identity (the submitter needs read-secret on it).
    secret_access {
      path = [[ $p | quote ]]
    }
    [[- end ]]

    # The admin entrypoint: /ping is the health check of Traefik.
    service {
      name     = [[ $job | quote ]]
      port     = "admin"
      provider = "nomad"
      tags     = ["admin"]

      check {
        type     = "http"
        path     = "/ping"
        interval = "10s"
        timeout  = "2s"
      }
    }
    [[- range $e := $v.entrypoints ]]

    # Entrypoint [[ $e.name ]] ([[ $e.protocol ]]).
    service {
      name     = [[ printf "%s-%s" $job $e.name | quote ]]
      port     = [[ printf "ep_%s" (replace "-" "_" $e.name) | quote ]]
      provider = "nomad"
      tags     = [[ list "entrypoint" $e.protocol | toStringList ]]
    }
    [[- end ]]

    task "traefik" {
      driver = "docker"

      config {
        image = [[ $image | quote ]]
        args  = ["--configfile=${NOMAD_TASK_DIR}/traefik.yml"]
        [[- if $host ]]
        network_mode = "host"
        [[- else ]]
        ports = [[ $labels | toStringList ]]
        [[- end ]]
      }

      # The workload identity (NOMAD_TOKEN) reads the catalog through the
      # task API socket.
      identity {
        env = true
      }

      # The static configuration: entrypoints, providers, logs. A change
      # restarts Traefik.
      template {
        destination = "local/traefik.yml"
        change_mode = "restart"
        data        = <<TRAEFIK_STATIC
global:
  checkNewVersion: false
  sendAnonymousUsage: false
log:
  level: [[ $v.log_level ]]
[[- if $v.access_log ]]
accessLog: {}
[[- end ]]
entryPoints:
  traefik:
    address: "[[ if $host ]]{{ env "NOMAD_IP_admin" }}[[ end ]]:[[ $v.admin_port ]]"
[[- range $e := $v.entrypoints ]]
  [[ $e.name ]]:
    address: "[[ if $host ]]{{ env "[[ printf "NOMAD_IP_ep_%s" (replace "-" "_" $e.name) ]]" }}[[ end ]]:[[ $e.port ]][[ if eq $e.protocol "udp" ]]/udp[[ end ]]"
[[- if ne $e.redirect_to "" ]]
    http:
      redirections:
        entryPoint:
          to: [[ $e.redirect_to ]]
          scheme: https
          permanent: true
[[- else if eq $e.protocol "https" ]]
    http:
      tls: {}
[[- end ]]
[[- end ]]
ping:
  entryPoint: traefik
[[- if $v.dashboard ]]
api:
  dashboard: true
  insecure: true
[[- end ]]
[[- if $v.metrics ]]
metrics:
  prometheus:
    entryPoint: traefik
[[- end ]]
providers:
  file:
    directory: "{{ env "NOMAD_SECRETS_DIR" }}/dynamic"
    watch: true
[[- if $v.catalog_enabled ]]
  nomad:
    exposedByDefault: [[ $v.exposed_by_default ]]
    namespaces: [[ $v.catalog_namespaces | toJson ]]
    endpoint:
      address: "[[ if ne $v.nomad_address "" ]][[ $v.nomad_address ]][[ else ]]unix://{{ env "NOMAD_SECRETS_DIR" }}/api.sock[[ end ]]"
      token: "{{ env "NOMAD_TOKEN" }}"
[[- end ]]
TRAEFIK_STATIC
      }

      # TLS: the options and the certificates of the secret store as PEM
      # content. Traefik watches the directory and applies a renewed
      # certificate without a restart.
      template {
        destination = "secrets/dynamic/tls.yml"
        change_mode = "noop"
        perms       = "0600"
        data        = <<TRAEFIK_TLS
tls:
  options:
    default:
      minVersion: [[ $v.tls_min_version ]]
[[- if gt (len $certs) 0 ]]
  certificates:
[[- range $p := $certs ]]
[[ template "traefik.certificate" (list $v $p "    - " "      " 8) ]]
[[- end ]]
[[- end ]]
[[- if ne $default "" ]]
  stores:
    default:
      defaultCertificate:
[[ template "traefik.certificate" (list $v $default "        " "        " 10) ]]
[[- end ]]
TRAEFIK_TLS
      }
      [[- if ne $v.dynamic_config "" ]]

      # The static routes of the pack (dynamic_config) unchanged: the
      # delimiters of the template keep it from being interpolated.
      template {
        destination     = "secrets/dynamic/routes.yml"
        change_mode     = "noop"
        left_delimiter  = "[%[%"
        right_delimiter = "%]%]"
        data            = <<TRAEFIK_ROUTES
[[ $v.dynamic_config | replace "${" "$${" | replace "%{" "%%{" | trimSuffix "\n" ]]
TRAEFIK_ROUTES
      }
      [[- end ]]

      resources {
        cpu    = [[ $v.resources.cpu ]]
        memory = [[ $v.resources.memory ]]
      }
    }
  }
}
