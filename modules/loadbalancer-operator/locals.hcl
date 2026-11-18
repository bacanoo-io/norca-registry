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

# The capabilities the rules of the ACL policy repeat.
locals {
  acl_capabilities        = ["list-jobs", "read-job", "submit-job"]
  acl_object_capabilities = ["read", "write", "write-status", "write-events", "manage-finalizers"]
}
