# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

locals {
  # The ID of the job and the prefix of its services; empty is the release.
  job       = coalesce(var.job_name, rigger.release)
  secrets   = var.secrets_variable != "" ? var.secrets_variable : "nomad/jobs/${local.job}"
  docker    = var.driver == "docker"
  clustered = var.count > 1
  routes    = local.clustered || var.gateway_enabled
  userpass  = var.auth_mode == "userpass"

  # The ports of the group: static unless the number is 0, bound to
  # host_network if set.
  ports = concat(
    [{ label = "client", number = var.client_port }],
    local.routes ? [{ label = "cluster", number = var.cluster_port }] : [],
    var.gateway_enabled ? [{ label = "gateway", number = var.gateway_port }] : [],
    var.leafnodes_enabled ? [{ label = "leafnode", number = var.leafnode_port }] : [],
    [{ label = "monitor", number = var.monitor_port }],
  )
  host_network = var.host_network == "" ? null : var.host_network

  # The address a listener binds: every address in a container, the
  # address of the port on the host.
  bind = { for p in ["client", "monitor", "cluster", "gateway", "leafnode"] : p => local.docker ? "0.0.0.0" : "{{ env \"NORCA_IP_${p}\" }}" }

  # The paths of the TLS material of the server.
  tls_files = [
    "ca_file: \"{{ env \"NORCA_SECRETS_DIR\" }}/tls/ca.pem\"",
    "cert_file: \"{{ env \"NORCA_SECRETS_DIR\" }}/tls/cert.pem\"",
    "key_file: \"{{ env \"NORCA_SECRETS_DIR\" }}/tls/key.pem\"",
  ]

  # A NATS string list: [ "a", "b" ].
  # The accounts of the users, in the order of their first user.
  accounts = distinct([for u in var.users : coalesce(u.account, var.users_default_account)])
  # The healthz path of the light checks.
  light = var.jetstream_enabled ? "/healthz?js-enabled-only=true" : "/healthz"
}

# The configuration of the server, line by line (a template of the task:
# {{ }} is consul-template). The lines of the template language are written
# as heredocs, where a backslash is the template's own.
locals {
  password_line = trimspace(<<-EOT
    password: "{{ with (nomadSecret "PATH").password }}{{ . | replaceAll "\\" "\\\\" | replaceAll "\"" "\\\"" }}{{ else }}{{ sprig_fail "the secret PATH has no item password" }}{{ end }}"
  EOT
  )
  token_lines = split("\n", trimsuffix(<<-EOT
    authorization {
      token: "{{ .client_token.Value | replaceAll "\\" "\\\\" | replaceAll "\"" "\\\"" }}"
    }
  EOT
  , "\n"))
  nkey_lines = split("\n", trimsuffix(<<-EOT
    authorization {
      users: [
      {{- range split "," (.client_nkeys.Value | replaceAll "\n" ",") }}{{ with trimSpace . }}
        { nkey: {{ toJSON . }} }
      {{- end }}{{ end }}
      ]
    }
  EOT
  , "\n"))

  # The permissions of a user, indented for the accounts block; nothing
  # without permissions.
  permissions = { for u in var.users : u.name => (
    length(u.publish_allow) + length(u.publish_deny) + length(u.subscribe_allow) + length(u.subscribe_deny) == 0 && !u.allow_responses ? [] : concat(
      ["        permissions: {"],
      length(u.publish_allow) + length(u.publish_deny) > 0 ? concat(
        ["          publish: {"],
        length(u.publish_allow) > 0 ? ["            allow: [ ${join(", ", [for s in u.publish_allow : jsonencode(s)])} ]"] : [],
        length(u.publish_deny) > 0 ? ["            deny: [ ${join(", ", [for s in u.publish_deny : jsonencode(s)])} ]"] : [],
        ["          }"],
      ) : [],
      length(u.subscribe_allow) + length(u.subscribe_deny) > 0 ? concat(
        ["          subscribe: {"],
        length(u.subscribe_allow) > 0 ? ["            allow: [ ${join(", ", [for s in u.subscribe_allow : jsonencode(s)])} ]"] : [],
        length(u.subscribe_deny) > 0 ? ["            deny: [ ${join(", ", [for s in u.subscribe_deny : jsonencode(s)])} ]"] : [],
        ["          }"],
      ) : [],
      u.allow_responses ? ["          allow_responses: true"] : [],
      ["        }"],
    )
  ) }

  # auth_mode = "userpass": the accounts with their users. The passwords
  # are read from the secret store when the template renders; a missing
  # password item fails the template instead of rendering an empty password
  # (which NATS would accept without a password).
  userpass_lines = concat(
    ["", ""],
    var.jetstream_enabled ? [
      "# auth_mode = \"userpass\": every account has its own subjects and",
      "# JetStream streams. The passwords (plain or bcrypt) come from the secret",
      ] : [
      "# auth_mode = \"userpass\": every account has its own subjects. The passwords (plain or bcrypt) come from the secret",
    ],
    [
      "# store (${var.users_secret_prefix}/<user>); a new version is applied with a reload.",
      "accounts {",
    ],
    flatten([for a in local.accounts : concat(
      ["  ${jsonencode(a)}: {"],
      var.jetstream_enabled && a != var.system_account ? ["    jetstream: enabled"] : [],
      ["    users: ["],
      flatten([for u in var.users : concat(
        [
          "      {",
          "        user: ${jsonencode(u.name)}",
          "        ${replace(local.password_line, "PATH", "${var.users_secret_prefix}/${u.name}")}",
        ],
        local.permissions[u.name],
        ["      }"],
      ) if coalesce(u.account, var.users_default_account) == a]),
      ["    ]", "  }"],
    )]),
    ["}"],
    contains(local.accounts, var.system_account) ? ["system_account: ${jsonencode(var.system_account)}"] : [],
  )

  auth_lines = local.userpass ? local.userpass_lines : var.auth_mode == "none" ? [] : concat(
    ["", "{{- with nomadVar \"${local.secrets}\" }}"],
    var.auth_mode == "token" ? local.token_lines : var.auth_mode == "nkey" ? local.nkey_lines : ["{{ .auth_config.Value }}"],
    ["{{- end }}"],
  )

  bus_account = var.norca_bus_account == "" && local.userpass ? var.users_default_account : var.norca_bus_account

  config = join("\n", concat(
    [
      "{{- $name := ${var.cluster_name != "" ? jsonencode(var.cluster_name) : "env \"NORCA_REGION\""} }}",
      "server_name: \"{{ $name }}-{{ env \"NORCA_ALLOC_INDEX\" }}\"",
      "listen: \"${local.bind.client}:{{ env \"NORCA_PORT_client\" }}\"",
      "client_advertise: \"{{ env \"NORCA_ADDR_client\" }}\"",
      "http: \"${local.bind.monitor}:{{ env \"NORCA_PORT_monitor\" }}\"",
      "lame_duck_duration: \"${var.lame_duck_duration}\"",
    ],
    var.jetstream_enabled ? concat(
      [
        "# Placement tags of JetStream: the Norca datacenter of the server",
        "# (unique_tag \"dc\" spreads the replicas over the datacenters).",
        "server_tags: [",
        "  \"dc:{{ env \"NORCA_DC\" }}\"",
      ],
      [for t in var.jetstream_server_tags : "  ${jsonencode(t)}"],
      ["]"],
    ) : [],
    ["lame_duck_grace_period: \"5s\""],
    var.debug ? ["debug: true"] : [],
    var.tls_enabled ? concat(["", "tls {"], [for f in local.tls_files : "  ${f}"], ["  verify: ${var.tls_verify_clients}", "  timeout: 5", "}"]) : [],
    local.auth_lines,
    var.jetstream_enabled ? concat(
      [
        "",
        "jetstream {",
        var.storage == "ephemeral_disk" ? "  store_dir: \"{{ env \"NORCA_ALLOC_DIR\" }}/data\"" : var.storage == "host_volume" ? "  store_dir: \"/data/{{ $name }}-{{ env \"NORCA_ALLOC_INDEX\" }}\"" : "  store_dir: \"${var.store_path}/{{ $name }}-{{ env \"NORCA_ALLOC_INDEX\" }}\"",
        "  max_memory_store: ${var.jetstream_max_memory}",
        "  max_file_store: ${var.jetstream_max_file}",
      ],
      var.jetstream_sync_interval != "" ? ["  sync_interval: ${jsonencode(var.jetstream_sync_interval)}"] : [],
      var.jetstream_max_outstanding_catchup != "" ? ["  max_outstanding_catchup: ${var.jetstream_max_outstanding_catchup}"] : [],
      var.jetstream_unique_tag != "" ? ["  # Replicas of a stream on servers of different datacenters.", "  unique_tag: ${jsonencode(var.jetstream_unique_tag)}"] : [],
      var.jetstream_domain != "" ? ["  domain: ${jsonencode(var.jetstream_domain)}"] : [],
      ["}"],
    ) : [],
    local.routes ? concat(
      [
        "",
        "cluster {",
        "  name: \"{{ $name }}\"",
        "  listen: \"${local.bind.cluster}:{{ env \"NORCA_PORT_cluster\" }}\"",
        "  advertise: \"{{ env \"NORCA_ADDR_cluster\" }}\"",
      ],
      var.cluster_compression != "" ? ["  compression: ${jsonencode(var.cluster_compression)}"] : [],
      var.cluster_pool_size != 0 ? ["  pool_size: ${var.cluster_pool_size}"] : [],
      [
        "  # The own address is always listed (the server ignores a route",
        "  # to itself): JetStream clustering needs at least one route.",
        "  routes: [",
        "    \"nats-route://{{ env \"NORCA_ADDR_cluster\" }}\"",
        "  {{- range nomadService \"${local.job}-cluster\" }}{{ if ne .AllocID (env \"NORCA_ALLOC_ID\") }}",
        "    \"nats-route://{{ .Address }}:{{ .Port }}\"",
        "  {{- end }}{{ end }}",
        "  ]",
      ],
      var.tls_enabled ? concat(["  tls {"], [for f in local.tls_files : "    ${f}"], ["    verify: true", "    timeout: 5", "  }"]) : [],
      ["}"],
    ) : [],
    var.gateway_enabled ? concat(
      [
        "",
        "gateway {",
        "  name: \"{{ $name }}\"",
        "  listen: \"${local.bind.gateway}:{{ env \"NORCA_PORT_gateway\" }}\"",
        "  advertise: \"{{ env \"NORCA_ADDR_gateway\" }}\"",
        "  gateways: [",
      ],
      [for g in var.remote_gateways : "    { name: ${jsonencode(g.name)}, urls: [ ${join(", ", [for u in g.urls : jsonencode(u)])} ] }"],
      ["  ]"],
      var.tls_enabled ? concat(["  tls {"], [for f in local.tls_files : "    ${f}"], ["    verify: true", "    timeout: 5", "  }"]) : [],
      ["}"],
    ) : [],
    var.leafnodes_enabled || var.norca_bus_leaf ? concat(
      ["", "leafnodes {"],
      var.leafnodes_enabled ? concat(
        [
          "  listen: \"${local.bind.leafnode}:{{ env \"NORCA_PORT_leafnode\" }}\"",
          "  advertise: \"{{ env \"NORCA_ADDR_leafnode\" }}\"",
        ],
        var.tls_enabled ? concat(["  tls {"], [for f in local.tls_files : "    ${f}"], ["    verify: ${var.tls_verify_clients}", "    timeout: 5", "  }"]) : [],
      ) : [],
      var.norca_bus_leaf ? concat(
        [
          "  # The system bus of the Norca servers (change data capture): the",
          "  # changes of the region, one way, with the ACL token of the item",
          "  # token of the secret ${var.norca_bus_secret} (without the line",
          "  # break a token file often ends with).",
          "  remotes: [",
          "    {",
          "      urls: [",
        ],
        [for s in var.norca_bus_servers : "        \"nats-leaf://{{ with (nomadSecret \"${var.norca_bus_secret}\").token }}{{ . | trimSpace }}{{ else }}{{ sprig_fail \"the secret ${var.norca_bus_secret} has no item token\" }}{{ end }}@${s}\""],
        ["      ]"],
        local.bus_account != "" ? ["      account: ${jsonencode(local.bus_account)}"] : [],
        var.norca_bus_tls ? [
          "      tls {",
          "        ca_file: \"{{ env \"NORCA_SECRETS_DIR\" }}/norca_bus/ca.pem\"",
          "        timeout: 5",
          "      }",
        ] : [],
        ["    }", "  ]"],
      ) : [],
      ["}"],
    ) : [],
    # extra_config as the pack indented it into the heredoc of the job: a
    # line with text as it is, a blank one (and the end) indented by 10.
    var.extra_config != "" ? concat([""], [for l in split("\n", var.extra_config) : trimspace(l) == "" ? "          ${l}" : l]) : [],
  ))
}
