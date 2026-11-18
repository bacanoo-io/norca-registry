# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

locals {
  mock   = var.driver == "mock_driver"
  docker = var.driver == "docker"

  # The namespace of the LoadBalancer objects the controller reconciles;
  # "*" for every namespace.
  watch  = var.watch_namespace != "" ? var.watch_namespace : rig.namespace
  all    = local.watch == "*"
  job_ns = rig.namespace
  tokens = var.class_token_namespace

  controller_args = concat(
    [
      "controller",
      "-objects", "native",
      "-namespace", local.watch,
      "-lease-namespace", rig.namespace,
      "-log-level", var.log_level,
      "-discover-services=${var.discover_services}",
      "-proxy-driver", var.proxy_driver,
    ],
    var.proxy_driver == "docker" ? ["-proxy-image", var.proxy_image] : var.proxy_driver != "mock_driver" ? ["-proxy-command", var.binary] : [],
    [
      "-metrics-addr", runtime_env("NORCA_ADDR_metrics"),
      "-class-ttl", var.class_ttl,
      "-class-token-namespace", var.class_token_namespace,
      "-class-allow-http=${var.class_allow_http}",
    ],
    var.class_ca_cert == "" ? [] : ["-class-ca-file", "${runtime_env("NORCA_TASK_DIR")}/class-ca.pem"],
  )

  webhook_args = [
    "webhook",
    "-listen", ":${runtime_env("NORCA_PORT_webhook")}",
    "-tls-cert", "${runtime_env("NORCA_SECRETS_DIR")}/webhook.pem",
    "-tls-key", "${runtime_env("NORCA_SECRETS_DIR")}/webhook-key.pem",
    "-classes", join(",", var.classes),
    "-default-class", var.default_class,
  ]

  variable_path = "nomad/jobs/${var.job_name}"
  webhook_url   = trimsuffix(var.webhook_url, "/")

  # The CEL check of one service's norca_lb_port mark (s is the service).
  port_mark_ok = "(!has(s.Meta) || s.Meta == null || !('norca_lb_port' in s.Meta) || (s.Meta.norca_lb_port.matches('^[0-9]{1,5}$') && int(s.Meta.norca_lb_port) >= 1 && int(s.Meta.norca_lb_port) <= 65535))"
}

# The rules of the ACL policy, line by line: which namespaces get which
# block depends on whether the controller watches every namespace and on
# where its job and the tokens of the classes are.
locals {
  # Read services, allocations and jobs; register and purge the proxy jobs
  # the operator owns.
  acl_capabilities = [
    "  # Read services, allocations and jobs; register and purge the proxy jobs",
    "  # (lb-*) the operator owns.",
    "  capabilities = [\"list-jobs\", \"read-job\", \"submit-job\"]",
  ]
  # The target lists of the proxy jobs.
  acl_proxy_variables = [
    "    # The target lists of the proxy jobs (the jobs' own Variables).",
    "    path \"nomad/jobs/lb-*\" {",
    "      capabilities = [\"list\", \"read\", \"write\", \"destroy\"]",
    "    }",
  ]
  # The LoadBalancer objects.
  acl_objects = [
    "",
    "  # The LoadBalancer objects: status, event log and the cleanup finalizer;",
    "  # \"write\" for the objects of marked services.",
    "  object \"norca.io/LoadBalancer\" {",
    "    capabilities = [\"read\", \"write\", \"write-status\", \"write-events\", \"manage-finalizers\"]",
    "  }",
  ]
  acl_leases = [
    "    # Leader election leases of the controller instances.",
    "    path \"controller-lease/loadbalancer*\" {",
    "      capabilities = [\"list\", \"read\", \"write\"]",
    "    }",
  ]
  acl_tokens = [
    "    # The tokens of the registered classes.",
    "    path ${jsonencode(var.class_token_path)} {",
    "      capabilities = [\"read\"]",
    "    }",
  ]

  acl_watch = concat(
    local.all ? [
      "# The namespace of the LoadBalancer objects the controller reconciles: every",
      "# namespace. A block of a namespace by name below takes the place of this",
      "# one for that namespace, so those blocks repeat these rules.",
    ] : ["# The namespace of the LoadBalancer objects the controller reconciles."],
    ["namespace \"${local.watch}\" {"],
    local.acl_capabilities,
    ["", "  variables {"],
    local.acl_proxy_variables,
    local.job_ns == local.watch ? concat([""], local.acl_leases) : [],
    local.tokens == local.watch ? concat([""], local.acl_tokens) : [],
    ["  }"],
    local.acl_objects,
    local.all ? [
      "",
      "  # The registered load balancer classes (cluster-scoped).",
      "  object \"norca.io/LoadBalancerClass\" {",
      "    capabilities = [\"read\"]",
      "  }",
    ] : [],
    ["}"],
  )

  acl_job = local.job_ns == local.watch ? [] : concat(
    ["", "# The namespace of the controller job: the leases of its instances.", "namespace \"${local.job_ns}\" {"],
    local.all ? concat(local.acl_capabilities, [""]) : [],
    ["  variables {"],
    local.all ? concat(local.acl_proxy_variables, [""]) : [],
    local.acl_leases,
    local.tokens == local.job_ns ? concat([""], local.acl_tokens) : [],
    ["  }"],
    local.all ? local.acl_objects : [],
    ["}"],
  )

  acl_token_ns = local.tokens == local.watch || local.tokens == local.job_ns ? [] : concat(
    ["", "# The namespace of the tokens of the registered classes.", "namespace \"${local.tokens}\" {"],
    local.all ? concat(local.acl_capabilities, [""]) : [],
    ["  variables {"],
    local.all ? concat(local.acl_proxy_variables, [""]) : [],
    local.acl_tokens,
    ["  }"],
    local.all ? local.acl_objects : [],
    ["}"],
  )

  acl_classes = local.all ? [] : [
    "",
    "# The registered load balancer classes are cluster-scoped: their rule is in",
    "# the namespace \"*\".",
    "namespace \"*\" {",
    "  object \"norca.io/LoadBalancerClass\" {",
    "    capabilities = [\"read\"]",
    "  }",
    "}",
  ]

  acl_rules = join("\n", concat(local.acl_watch, local.acl_job, local.acl_token_ns, local.acl_classes, [
    "",
    "# The nodes of the instances: an instance on a node marked as leaving",
    "# (norca.lb.leaving, set by the node scaling operator before a drain) is not",
    "# a target; node events reconcile the load balancers.",
    "node {",
    "  policy = \"read\"",
    "}",
  ]))
}
