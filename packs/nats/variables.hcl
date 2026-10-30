# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------

variable "job_name" {
  description = "Name of the NATS job. Empty uses the pack name (\"nats\"). It also prefixes the service names (<job>, <job>-cluster, <job>-gateway, <job>-monitor, <job>-leafnode) and sets the default Variable path nomad/jobs/<job>."
  type        = string
  default     = ""
}

variable "region" {
  description = "Region of the jobs. Empty leaves it to the region the pack is submitted to. Deploy the pack once per region (one region per cloud)."
  type        = string
  default     = ""
}

variable "namespace" {
  description = "Namespace of the jobs. Empty uses the namespace of the submitter (default)."
  type        = string
  default     = ""
}

variable "datacenters" {
  description = "Datacenters eligible for placement."
  type        = list(string)
  default     = ["*"]
}

variable "node_pool" {
  description = "Node pool of the jobs. Empty uses the default node pool."
  type        = string
  default     = ""
}

variable "count" {
  description = "Number of NATS servers in the region. Use an odd number of at least 3: JetStream needs a majority of the servers for its Raft groups."
  type        = number
  default     = 3
}

variable "distinct_hosts" {
  description = "Place every NATS server on a different node (distinct_hosts constraint). Disable it only for tests on a single node."
  type        = bool
  default     = true
}

variable "separate_scope" {
  description = "Optional topology domain for the fork's separate block, e.g. \"$${node.datacenter}\" (one datacenter per availability zone): the servers avoid sharing a domain. Empty renders no separate block."
  type        = string
  default     = ""
}

variable "separate_required" {
  description = "Make the separate rule mandatory instead of a preference. With fewer domains than servers the placement then blocks."
  type        = bool
  default     = false
}

variable "host_network" {
  description = "Client host_network to bind the ports to, e.g. the WireGuard interface of the VPN. Empty uses the default network."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Runtime: Docker or a nats-server binary
# ---------------------------------------------------------------------------

variable "driver" {
  description = "Task driver: \"docker\" (official nats image), \"raw_exec\" or \"exec\" (a nats-server binary on the node or downloaded with artifact_url)."
  type        = string
  default     = "docker"
}

variable "image" {
  description = "Docker image of the server (driver = docker). The official image is Apache-2.0 licensed."
  type        = string
  default     = "nats:2.15.0"
}

variable "binary" {
  description = "Path of nats-server for raw_exec/exec: absolute on the node, or relative to the task directory when downloaded with artifact_url (e.g. local/nats-server-v2.15.0-linux-amd64/nats-server)."
  type        = string
  default     = "/usr/local/bin/nats-server"
}

variable "artifact_url" {
  description = "Optional URL of a nats-server release archive for raw_exec/exec, unpacked into the task directory, e.g. https://github.com/nats-io/nats-server/releases/download/v2.15.0/nats-server-v2.15.0-linux-amd64.tar.gz. Empty uses binary as is."
  type        = string
  default     = ""
}

variable "artifact_checksum" {
  description = "Checksum of the artifact, e.g. \"sha256:<hex>\" (recommended). Empty skips the check."
  type        = string
  default     = ""
}

variable "resources" {
  description = "CPU (MHz) and memory (MB) of a NATS server."
  type = object({
    cpu    = number
    memory = number
  })
  default = {
    cpu    = 500
    memory = 512
  }
}

# ---------------------------------------------------------------------------
# Ports (0 = dynamic port)
# ---------------------------------------------------------------------------

variable "client_port" {
  description = "Client port. Static by default so clients and leaf nodes have a fixed address; 0 picks a dynamic port."
  type        = number
  default     = 4222
}

variable "cluster_port" {
  description = "Cluster (route) port between the servers of the region; 0 picks a dynamic port (routes are discovered through the <job>-cluster service)."
  type        = number
  default     = 6222
}

variable "gateway_port" {
  description = "Gateway port for the supercluster. Keep it static: the other regions reach it over the VPN at a fixed address."
  type        = number
  default     = 7222
}

variable "monitor_port" {
  description = "HTTP monitoring port (/varz, /routez, /gatewayz, /jsz, /healthz); also used by the health checks."
  type        = number
  default     = 8222
}

variable "leafnode_port" {
  description = "Leaf node port (only with leafnodes_enabled)."
  type        = number
  default     = 7422
}

# ---------------------------------------------------------------------------
# Cluster, gateways, leaf nodes
# ---------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name of the cluster of this region, which is also its gateway name in the supercluster. Empty uses the Norca region of the job (NOMAD_REGION). Must be unique per region."
  type        = string
  default     = ""
}

variable "cluster_compression" {
  description = "Compression of the routes between the servers: \"s2_auto\" (by the round trip time; for servers in several datacenters), \"s2_fast\", \"s2_better\", \"s2_best\", \"accept\" (only if the other side asks) or \"off\". Empty: the server default (accept)."
  type        = string
  default     = ""

  validation {
    pattern = "^(|off|accept|s2_auto|s2_fast|s2_better|s2_best)$"
  }
}

variable "cluster_pool_size" {
  description = "Route connections between two servers (route pooling); 0: the server default (3), -1: one connection. All servers must use the same value: changing it disconnects the routes until every server runs with the new value."
  type        = number
  default     = 0

  validation {
    min     = -1
    max     = 32
    integer = true
  }
}

variable "gateway_enabled" {
  description = "Enable the gateway listener to join a supercluster with the other regions."
  type        = bool
  default     = false
}

variable "remote_gateways" {
  description = "The gateways of the other regions: name (their cluster_name) and URLs reachable over the VPN, e.g. [{name = \"gcp\", urls = [\"nats://10.20.0.11:7222\", \"nats://10.20.0.12:7222\"]}]. One URL per remote cluster is enough, the rest is discovered."
  type = list(object({
    name = string
    urls = list(string)
  }))
  default = []
}

variable "leafnodes_enabled" {
  description = "Enable the leaf node listener, for edge servers that connect to this region as leaf nodes."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# JetStream
# ---------------------------------------------------------------------------

variable "jetstream_enabled" {
  description = "Enable JetStream (durable streams)."
  type        = bool
  default     = true
}

variable "jetstream_domain" {
  description = "Optional JetStream domain. All clusters of a supercluster share one domain; leave it empty unless leaf nodes run their own domains."
  type        = string
  default     = ""
}

variable "jetstream_max_memory" {
  description = "max_memory_store of a server, e.g. \"256MB\"."
  type        = string
  default     = "256MB"
}

variable "jetstream_max_file" {
  description = "max_file_store of a server, e.g. \"1GB\". Keep it below the size of the storage (ephemeral_disk_size)."
  type        = string
  default     = "1GB"
}

variable "storage" {
  description = "Where JetStream keeps its data: \"ephemeral_disk\" (sticky, migrated ephemeral disk), \"host_volume\" (the client host volume host_volume; docker and exec) or \"path\" (store_path on the node, for raw_exec)."
  type        = string
  default     = "ephemeral_disk"
}

variable "ephemeral_disk_size" {
  description = "Size of the ephemeral disk in MB (storage = ephemeral_disk)."
  type        = number
  default     = 2048
}

variable "host_volume" {
  description = "Name of the client host volume (storage = host_volume). Every server keeps its data in a subdirectory named after the server."
  type        = string
  default     = "nats"
}

variable "store_path" {
  description = "Directory on the node for the data (storage = path). Every server keeps its data in a subdirectory named after the server."
  type        = string
  default     = ""
}

variable "jetstream_unique_tag" {
  description = "Spread the replicas of every stream over the datacenters: \"dc\" makes JetStream place the replicas on servers with different dc:<datacenter> tags (every server has the tag of its Norca datacenter). Needs at least as many datacenters with a server as the replicas of a stream. Empty: replicas only on different servers."
  type        = string
  default     = ""

  validation {
    pattern = "^([a-z0-9_-]+)?$"
  }
}

variable "jetstream_server_tags" {
  description = "Further tags of every server (besides dc:<datacenter>), for the placement of streams (nats stream add --tag)."
  type        = list(string)
  default     = []
}

variable "jetstream_sync_interval" {
  description = "How often JetStream syncs its files to disk: a duration (\"2m\", the server default when empty) or \"always\" (every write, slower). Replicated streams (R3) keep the data when one server loses its unsynced writes."
  type        = string
  default     = ""

  validation {
    pattern = "^(always|[0-9]+(ms|s|m|h))?$"
  }
}

variable "jetstream_max_outstanding_catchup" {
  description = "Maximum data in flight while a server catches up on a stream, e.g. \"64MB\" (the server default when empty). Lower it when the servers are joined by a slow link between the datacenters."
  type        = string
  default     = ""

  validation {
    pattern = "^([0-9]+([KMGT]i?B?)?)?$"
  }
}

# ---------------------------------------------------------------------------
# Secrets: TLS and client authentication from a Variable
# ---------------------------------------------------------------------------

variable "secrets_variable" {
  description = "Path of the Variable holding the TLS certificates and the client credentials of the token, nkey and config modes (auth_mode = \"userpass\" reads the secret store instead). Empty uses nomad/jobs/<job>, which the job reads with its workload identity without any policy."
  type        = string
  default     = ""
}

variable "tls_enabled" {
  description = "TLS on the client, route, gateway and leaf node ports, from the items tls_ca, tls_cert and tls_key of the secrets Variable. Routes and gateways verify each other's certificates (mutual TLS). Disable only for development or when the VPN is the only transport protection."
  type        = bool
  default     = false
}

variable "tls_verify_clients" {
  description = "Require client certificates on the client and leaf node ports as well."
  type        = bool
  default     = false
}

variable "auth_mode" {
  description = "Client authentication: \"none\", \"token\" (item client_token), \"nkey\" (item client_nkeys: public user NKeys, comma or newline separated), \"config\" (item auth_config: a raw NATS config snippet with authorization/accounts or operator/resolver settings for JWT credentials) or \"userpass\" (the users of the variable users in NATS accounts, their passwords from the built-in secret store; no Variable item)."
  type        = string
  default     = "none"

  ui {
    options = ["none", "token", "nkey", "config", "userpass"]
  }
}

# ---------------------------------------------------------------------------
# Users and accounts (auth_mode = "userpass"), passwords from the secret store
# ---------------------------------------------------------------------------

variable "users" {
  description = "auth_mode = \"userpass\": the NATS users. name: the user name. account: its NATS account (empty: users_default_account); every account has its own subjects and, with JetStream, its own streams and KV buckets. publish_allow, publish_deny, subscribe_allow, subscribe_deny: subject permissions inside the account (empty lists: no restriction). allow_responses: may reply to the requests it receives without a publish permission for the reply subjects. The password is never a variable: it is the item password of the secret <users_secret_prefix>/<name> in the namespace of the job (plain, or a bcrypt hash made with nats server passwd)."
  type = list(object({
    name            = string
    account         = optional(string, "")
    publish_allow   = optional(list(string), [])
    publish_deny    = optional(list(string), [])
    subscribe_allow = optional(list(string), [])
    subscribe_deny  = optional(list(string), [])
    allow_responses = optional(bool, false)
  }))
  default = []
}

variable "users_secret_prefix" {
  description = "auth_mode = \"userpass\": prefix of the secret paths of the users: the password of a user is the item password of <users_secret_prefix>/<name>."
  type        = string
  default     = "nats/users"

  validation {
    pattern = "^[a-zA-Z0-9_-]+(/[a-zA-Z0-9_-]+)*$"
  }
}

variable "users_default_account" {
  description = "auth_mode = \"userpass\": account of the users without an account."
  type        = string
  default     = "APP"

  validation {
    pattern = "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$"
  }
}

variable "system_account" {
  description = "auth_mode = \"userpass\": users with this account are in the system account of the servers (the nats CLI's server commands: server report, raft peer-remove, ...). It has no JetStream. Without such a user the servers keep their internal system account."
  type        = string
  default     = "SYS"

  validation {
    pattern = "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$"
  }
}

# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------

variable "disruption_max_unavailable" {
  description = "max_unavailable of the disruption block (fork feature), limiting node drains and evictions so the JetStream quorum survives. Empty renders no disruption block."
  type        = string
  default     = "1"
}

variable "startup_timeout" {
  description = "startup_timeout of the startup check: the server is restarted if it is not up with JetStream enabled within this time."
  type        = string
  default     = "5m"
}

variable "healthy_deadline" {
  description = "healthy_deadline of the update and migrate blocks. A restarted server is healthy (readiness /healthz) only after its streams caught up; raise it for large streams."
  type        = string
  default     = "10m"
}

variable "lame_duck_duration" {
  description = "Lame duck duration: on stop the server stops accepting clients and moves them away over this time before shutting down (kill_signal SIGUSR2). nats-server requires at least 30s."
  type        = string
  default     = "30s"
}

variable "kill_timeout" {
  description = "kill_timeout of the server task; keep it above lame_duck_duration plus a few seconds for the JetStream shutdown."
  type        = string
  default     = "45s"
}

variable "debug" {
  description = "Enable debug logging of the server."
  type        = bool
  default     = false
}

variable "extra_config" {
  description = "Raw NATS configuration appended to the generated file (e.g. websocket or mqtt blocks). It is part of a Nomad template: escape {{ as {{\"{{\"}}."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Metrics: Prometheus exporter (optional)
# ---------------------------------------------------------------------------

variable "metrics_enabled" {
  description = "Run the NATS Prometheus exporter (prometheus-nats-exporter, Apache-2.0) next to every server: it polls the monitoring port and serves /metrics, registered as the service <job>-metrics (scraped by the otel-collector pack). nats-server itself has no Prometheus endpoint."
  type        = bool
  default     = false
}

variable "metrics_image" {
  description = "Image of the exporter (docker driver, also next to raw_exec and exec servers)."
  type        = string
  default     = "docker.io/natsio/prometheus-nats-exporter:0.20.2"
}

variable "metrics_port" {
  description = "Port of the exporter on the node; 0 (default) picks a dynamic port, which the collector finds through the catalog."
  type        = number
  default     = 0
}

variable "metrics_resources" {
  description = "CPU (MHz) and memory (MB) of the exporter."
  type = object({
    cpu    = number
    memory = number
  })
  default = {
    cpu    = 50
    memory = 64
  }
}

# ---------------------------------------------------------------------------
# Rules: conditions on the items of lists and maps and across variables,
# checked before rendering by the CLI and by the servers that render the pack.
# ---------------------------------------------------------------------------

rule "users" {
  condition = alltrue([
    for u in var.users :
    can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$", u.name)) &&
    (try(u.account, "") == "" || can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$", try(u.account, "")))) &&
    alltrue([
      for subjects in [for k in ["publish_allow", "publish_deny", "subscribe_allow", "subscribe_deny"] : try(u[k], [])] :
      length(distinct(subjects)) == length(subjects) &&
      alltrue([for subject in subjects : can(regex("^(([^\\s.*>\"'\\\\{}]+|\\*)\\.)*([^\\s.*>\"'\\\\{}]+|\\*|>)$", subject))])
    ])
  ])
  error_message = "users: name must match ^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$; account must be empty or match it; publish_allow, publish_deny, subscribe_allow and subscribe_deny must hold NATS subjects (tokens separated by dots, * for one token, > as the last token) without duplicates."
}

rule "users_userpass" {
  condition     = var.auth_mode != "userpass" || length(var.users) > 0
  error_message = "users needs at least 1 item when auth_mode is userpass."
}

rule "users_without_userpass" {
  condition     = var.auth_mode == "userpass" || length(var.users) == 0
  error_message = "users must be empty when auth_mode is not userpass."
}
