# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

locals {
  # The ID of the server job and the prefix of the others; empty is the
  # release.
  job          = coalesce(var.job_name, rigger.release)
  tls          = var.tls_enabled
  docker       = var.driver == "docker"
  host_network = var.host_network == "" ? null : var.host_network

  src_var    = "nomad/jobs/${local.job}/servers/bootstrap"
  server_var = "nomad/jobs/${local.job}/servers"
  client_var = "nomad/jobs/${local.job}-clients"
  snapshot   = "${local.job}-snapshot"

  api        = local.tls ? "https" : "http"
  local_addr = local.tls ? "127.0.0.1" : "127.0.0.1 {{ $ip }}"
  data_dir   = var.driver == "raw_exec" ? var.server_data_path : "/consul/data"

  # The official image: <registry>/<repository>:<tag>[@<digest>].
  image_ref = "${var.image_registry != "" ? "${var.image_registry}/" : ""}${var.image_repository}:${var.image_tag != "" ? var.image_tag : var.consul_version}"
  image     = var.image_digest != "" ? "${local.image_ref}@${var.image_digest}" : local.image_ref

  # The official release archive (exec, raw_exec), unpacked into local/.
  download_url = "${trimsuffix(var.download_base_url, "/")}/${var.consul_version}/consul_${var.consul_version}_linux_${var.download_arch}.zip"
  artifacts    = !local.docker && var.consul_binary == "" ? [local.download_url] : []

  # The consul binary as seen by a script task.
  consul_bin = local.docker ? "consul" : var.consul_binary != "" ? var.consul_binary : "${runtime_env("NORCA_TASK_DIR")}/consul"
  # The agent itself.
  agent_command = var.consul_binary != "" ? var.consul_binary : "local/consul"
  agent_args    = ["agent", "-config-dir=${runtime_env("NORCA_SECRETS_DIR")}/consul.d"]

  # The ports of the servers and of the clients, static, bound to
  # host_network if set.
  server_ports = merge(
    { server = var.port_server, serf_lan = var.port_serf_lan, serf_wan = var.port_serf_wan, http = var.port_http, grpc = var.port_grpc },
    local.tls ? { https = var.port_https, grpc_tls = var.port_grpc_tls } : {},
    { dns = var.port_dns },
  )
  server_port_order = concat(["server", "serf_lan", "serf_wan", "http", "grpc"], local.tls ? ["https", "grpc_tls"] : [], ["dns"])
  client_port_order = concat(["serf_lan", "http", "grpc"], local.tls ? ["https", "grpc_tls"] : [], ["dns"])

  join = "{\"retry_join\": [{{ range $i, $s := nomadService \"${local.job}-serf\" }}{{ if $i }}, {{ end }}\"{{ $s.Address }}:{{ $s.Port }}\"{{ end }}]}\n"

  # extra configuration as the pack indented it into the heredoc of the job:
  # a line with text as it is, a blank one (and the end) indented by 10.
  server_extra = var.server_extra_config == "" ? [] : concat([""], [for l in split("\n", var.server_extra_config) : trimspace(l) == "" ? "          ${l}" : l])
  client_extra = var.client_extra_config == "" ? [] : concat([""], [for l in split("\n", var.client_extra_config) : trimspace(l) == "" ? "          ${l}" : l])

  telemetry = var.metrics_enabled ? [
    "",
    "# /v1/agent/metrics?format=prometheus (ACL agent:read).",
    "telemetry {",
    "  prometheus_retention_time = \"${var.metrics_retention_time}\"",
    "  disable_hostname          = true",
    "}",
  ] : []

  addresses = concat(
    [
      "bind_addr      = \"{{ $ip }}\"",
      "advertise_addr = \"{{ $ip }}\"",
      "client_addr    = \"127.0.0.1\"",
      "addresses {",
      "  http     = \"${local.local_addr}\"",
      "  grpc     = \"${local.local_addr}\"",
    ],
    local.tls ? ["  https    = \"127.0.0.1 {{ $ip }}\"", "  grpc_tls = \"127.0.0.1 {{ $ip }}\""] : [],
    ["  dns      = \"${var.dns_address}\"", "}"],
  )

  # The configuration of a server.
  server_config = join("\n", concat(
    [
      "{{- with nomadVar \"${local.server_var}\" }}",
      "{{- $ip := env \"NORCA_IP_serf_lan\" }}",
      "datacenter       = \"${var.datacenter}\"",
      "domain           = \"${var.domain}\"",
      "server           = true",
      "bootstrap_expect = ${var.server_count}",
      "data_dir         = \"${local.data_dir}\"",
      "log_level        = \"${var.log_level}\"",
      "",
      "leave_on_terminate      = false",
      "skip_leave_on_interrupt = true",
      "disable_update_check    = true",
      "",
    ],
    local.tls ? [
      "# Gossip and RPC on the private network; plain HTTP and gRPC on",
      "# localhost only, HTTPS and gRPC-TLS on localhost and the private",
      "# network. Never on a public network.",
      ] : [
      "# Gossip, RPC and the APIs on localhost and the private network",
      "# only, never on a public network.",
    ],
    local.addresses,
    [
      "ports {",
      "  server   = ${var.port_server}",
      "  serf_lan = ${var.port_serf_lan}",
      "  serf_wan = ${var.port_serf_wan}",
      "  http     = ${var.port_http}",
      "  https    = ${local.tls ? var.port_https : -1}",
      "  grpc     = ${var.port_grpc}",
      "  grpc_tls = ${local.tls ? var.port_grpc_tls : -1}",
      "  dns      = ${var.port_dns}",
      "}",
      "",
      "ui_config {",
      "  enabled = ${var.ui_enabled}",
      "}",
    ],
    local.telemetry,
    [
      "",
      "performance {",
      "  raft_multiplier = 1",
      "}",
      "",
      "encrypt                 = \"{{ .gossip_key.Value | trimSpace }}\"",
      "encrypt_verify_incoming = true",
      "encrypt_verify_outgoing = true",
      "",
      "# Mandatory ACLs, default deny, no anonymous access. The",
      "# initial_management token bootstraps the ACL system on the first",
      "# leader election; the acl-setup task creates the agent token.",
      "acl {",
      "  enabled                  = true",
      "  default_policy           = \"deny\"",
      "  down_policy              = \"extend-cache\"",
      "  enable_token_persistence = true",
      "  tokens {",
      "    initial_management = \"{{ .management_token.Value | trimSpace }}\"",
      "    agent              = \"{{ .agent_token.Value | trimSpace }}\"",
      "  }",
      "}",
    ],
    local.tls ? [
      "",
      "tls {",
      "  defaults {",
      "    ca_file         = \"{{ env \"NORCA_SECRETS_DIR\" }}/tls/ca_cert.pem\"",
      "    cert_file       = \"{{ env \"NORCA_SECRETS_DIR\" }}/tls/server_cert.pem\"",
      "    key_file        = \"{{ env \"NORCA_SECRETS_DIR\" }}/tls/server_key.pem\"",
      "    verify_incoming = true",
      "    verify_outgoing = true",
      "  }",
      "  internal_rpc {",
      "    verify_server_hostname = true",
      "  }",
      "  https {",
      "    verify_incoming = false",
      "  }",
      "  grpc {",
      "    verify_incoming = false",
      "  }",
      "}",
      "",
      "# The clients get their certificates from the servers.",
      "auto_encrypt {",
      "  allow_tls = true",
      "}",
    ] : [],
    ["{{- end }}"],
    local.server_extra,
  ))

  # The configuration of a client agent.
  client_config = join("\n", concat(
    [
      "{{- with nomadVar \"${local.client_var}\" }}",
      "{{- $ip := env \"NORCA_IP_serf_lan\" }}",
      "datacenter = \"${var.datacenter}\"",
      "domain     = \"${var.domain}\"",
      "server     = false",
      "data_dir   = \"{{ env \"NORCA_ALLOC_DIR\" }}/data/consul\"",
      "log_level  = \"${var.log_level}\"",
      "",
      "leave_on_terminate   = true",
      "disable_update_check = true",
      "",
    ],
    local.addresses,
    [
      "ports {",
      "  serf_lan = ${var.port_serf_lan}",
      "  http     = ${var.port_http}",
      "  https    = ${local.tls ? var.port_https : -1}",
      "  grpc     = ${var.port_grpc}",
      "  grpc_tls = ${local.tls ? var.port_grpc_tls : -1}",
      "  dns      = ${var.port_dns}",
      "}",
      "",
      "encrypt                 = \"{{ .gossip_key.Value | trimSpace }}\"",
      "encrypt_verify_incoming = true",
      "encrypt_verify_outgoing = true",
    ],
    local.telemetry,
    [
      "",
      "acl {",
      "  enabled                  = true",
      "  default_policy           = \"deny\"",
      "  down_policy              = \"extend-cache\"",
      "  enable_token_persistence = true",
      "  tokens {",
      "    agent = \"{{ .agent_token.Value | trimSpace }}\"",
      "  }",
      "}",
    ],
    local.tls ? [
      "",
      "# Only the CA: the client certificate comes from the servers.",
      "tls {",
      "  defaults {",
      "    ca_file         = \"{{ env \"NORCA_SECRETS_DIR\" }}/tls/ca_cert.pem\"",
      "    verify_incoming = false",
      "    verify_outgoing = true",
      "  }",
      "  internal_rpc {",
      "    verify_server_hostname = true",
      "  }",
      "}",
      "",
      "auto_encrypt {",
      "  tls = true",
      "}",
    ] : [],
    ["{{- end }}"],
    local.client_extra,
  ))
}

# The scripts of the tasks, assembled from heredocs.
locals {
  bootstrap_script = join("", [
    <<-EOT
      #!/bin/sh
      # Bootstrap of the Consul servers of job ${local.job} (consul pack). Runs
      # before every server start; the secrets are generated only once.
      set -eu
      umask 077
      norca="$NORCA_BIN"
      src="${local.src_var}"
      work="$NORCA_SECRETS_DIR/bootstrap"
      rm -rf "$work"
      mkdir -p "$work"
      cd "$work"

      if "$norca" var get -item=gossip_key "$src" >/dev/null 2>&1; then
        echo "bootstrap: using the secrets in $src"
      else
        echo "bootstrap: generating the gossip key, CA, server certificate and ACL tokens"
        "$norca" operator gossip keyring generate >gossip_key
        "$norca" tls ca create -days=${var.ca_days} >/dev/null
        "$norca" tls cert create -server -region=${jsonencode(var.datacenter)} -domain=${jsonencode(var.domain)} \
          -days=${var.cert_days} -ca=norca-agent-ca.pem -key=norca-agent-ca-key.pem >/dev/null
        mv norca-agent-ca.pem ca_cert
        mv norca-agent-ca-key.pem ca_key
        mv "${var.datacenter}-server-${var.domain}.pem" server_cert
        mv "${var.datacenter}-server-${var.domain}-key.pem" server_key
        for t in management_token agent_token agent_accessor snapshot_token snapshot_accessor; do
          cat /proc/sys/kernel/random/uuid >"$t"
        done
        # Created only if it does not exist: when several servers start at
        # the same time one of them wins, and all continue with its secrets.
        "$norca" var put -out=none -check-index=0 "$src" \
          gossip_key=@gossip_key ca_cert=@ca_cert ca_key=@ca_key \
          server_cert=@server_cert server_key=@server_key \
          management_token=@management_token agent_token=@agent_token agent_accessor=@agent_accessor \
          snapshot_token=@snapshot_token snapshot_accessor=@snapshot_accessor ||
          echo "bootstrap: $src was created by another server, using it"
        rm -f ./*
      fi

      # The Variables the tasks read are derived from the source on every
      # start (the CA key stays in the source only).
      items="gossip_key ca_cert server_cert server_key management_token agent_token agent_accessor snapshot_token snapshot_accessor"
      for item in $items; do
        "$norca" var get -item="$item" "$src" >"$item"
      done
      "$norca" var put -out=none -force "${local.server_var}" \
        gossip_key=@gossip_key ca_cert=@ca_cert server_cert=@server_cert server_key=@server_key \
        management_token=@management_token agent_token=@agent_token agent_accessor=@agent_accessor \
        snapshot_token=@snapshot_token snapshot_accessor=@snapshot_accessor
    EOT
    ,
    var.clients_enabled ? <<-EOT
      "$norca" var put -out=none -force "${local.client_var}" \
        gossip_key=@gossip_key ca_cert=@ca_cert agent_token=@agent_token
    EOT
    : "",
    var.snapshot_enabled ? <<-EOT
      "$norca" var put -out=none -force "nomad/jobs/${local.snapshot}/snapshot" \
        consul_token=@snapshot_token
    EOT
    : "",
    <<-EOT
      cd /
      rm -rf "$work"

      # Wait (at most 5 minutes) until every server is registered, so that
      # the retry_join lists of the first start contain each other.
      i=0
      while [ "$i" -lt 60 ]; do
        n=$("$norca" service info -json "${local.job}-serf" 2>/dev/null | grep -c '"AllocID"' || true)
        if [ "$n" -ge ${var.server_count} ]; then
          break
        fi
        echo "bootstrap: $n of ${var.server_count} servers registered, waiting"
        i=$((i + 1))
        sleep 5
      done
      echo "bootstrap: done"
    EOT
  ])

  acl_setup_script = join("", [
    <<-EOT
      #!/bin/sh
      # ACL setup of the Consul servers of job ${local.job} (consul pack).
      set -u
      consul="$CONSUL_BIN"
      mgmt="$NORCA_SECRETS_DIR/management_token"
      . "$NORCA_SECRETS_DIR/accessors.env"

      until "$consul" operator raft list-peers -token-file="$mgmt" >/dev/null 2>&1; do
        echo "acl-setup: waiting for the cluster to elect a leader"
        sleep 5
      done

      # ensure_policy <name> <description> <rules file>
      ensure_policy() {
        until "$consul" acl policy read -name="$1" -token-file="$mgmt" >/dev/null 2>&1; do
          "$consul" acl policy create -name="$1" -description="$2" -rules="@$3" \
            -token-file="$mgmt" >/dev/null || sleep 3
        done
      }

      # ensure_token <accessor> <secret file> <policy> <description>
      ensure_token() {
        until "$consul" acl token read -self -token-file="$2" >/dev/null 2>&1; do
          "$consul" acl token create -accessor="$1" -secret="$(cat "$2")" -policy-name="$3" \
            -description="$4" -token-file="$mgmt" >/dev/null || sleep 3
        done
      }

      ensure_policy norca-agent "Consul agents installed by the Norca consul pack" \
        "$NORCA_TASK_DIR/agent-policy.hcl"
      ensure_token "$AGENT_ACCESSOR" "$NORCA_SECRETS_DIR/agent_token" norca-agent \
        "Agent token of the Consul agents of job ${local.job}"
    EOT
    ,
    var.metrics_enabled ? <<-EOT
      ensure_policy norca-metrics "Agent metrics for the Norca otel-collector pack" \
        "$NORCA_TASK_DIR/metrics-policy.hcl"
      # The token has the secret ID of the secret store; its accessor is
      # generated by Consul.
      until "$consul" acl token read -self -token-file="$NORCA_SECRETS_DIR/metrics_token" >/dev/null 2>&1; do
        "$consul" acl token create -secret="$(cat "$NORCA_SECRETS_DIR/metrics_token")" -policy-name=norca-metrics \
          -description="Metrics token of the Norca otel-collector pack" -token-file="$mgmt" >/dev/null || sleep 3
      done
    EOT
    : "",
    var.snapshot_enabled ? <<-EOT
      ensure_policy norca-snapshot "Snapshots of the Norca consul pack" \
        "$NORCA_TASK_DIR/snapshot-policy.hcl"
      ensure_token "$SNAPSHOT_ACCESSOR" "$NORCA_SECRETS_DIR/snapshot_token" norca-snapshot \
        "Snapshot token of job ${local.snapshot}"
    EOT
    : "",
    "echo \"acl-setup: done\"\n",
  ])

  snapshot_aws_config = join("\n", concat(
    ["[default]", "region = ${var.snapshot_s3_region}"],
    var.snapshot_s3_path_style ? ["s3 =", "  addressing_style = path"] : [],
    [""],
  ))

  snapshot_upload = join("\n", [
    "#!/bin/sh",
    "set -eu",
    "key=\"${trimsuffix(var.snapshot_s3_prefix, "/")}/${var.datacenter}/$(date -u +%Y%m%dT%H%M%SZ).snap\"",
    join("", [
      "aws s3 cp \"$NORCA_ALLOC_DIR/data/consul.snap\" \"s3://${var.snapshot_s3_bucket}/$key\"",
      var.snapshot_s3_endpoint != "" ? " \\\n  --endpoint-url \"${var.snapshot_s3_endpoint}\"" : "",
      var.snapshot_s3_sse != "" ? " \\\n  --sse \"${var.snapshot_s3_sse}\"" : "",
    ]),
    "rm -f \"$NORCA_ALLOC_DIR/data/consul.snap\"",
    "echo \"snapshot: uploaded s3://${var.snapshot_s3_bucket}/$key\"",
    "",
  ])
}
