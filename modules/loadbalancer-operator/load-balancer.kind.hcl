# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The LoadBalancer objects (loadbalancer/operator of norca-platform).
kind "load-balancer" {
  enabled = var.loadbalancer_kind_enabled

  name        = "LoadBalancer"
  group       = "norca.io"
  description = "Load balancer forwarding to the healthy instances of a Nomad service"
  namespaced  = true
  version     = 1
  # The JSON Schema of the kind (loadbalancer.schema.json of norca-platform).
  # With the webhooks, the defaulting webhook fills in the class of the
  # region instead of the static default.
  schema = <<EOT
{
  "type": "object",
  "properties": {
    "spec": {
      "type": "object",
      "required": ["service", "port"],
      "additionalProperties": false,
      "properties": {
        "service":     {"type": "string", "minLength": 1},
        "class":       {"type": "string", "minLength": 1${var.webhook_enabled ? "" : ", \"default\": \"nomad\""}},
        "port":        {"type": "integer", "minimum": 1, "maximum": 65535},
        "internal":    {"type": "boolean", "default": false},
        "replicas":    {"type": "integer", "minimum": 1, "maximum": 16, "default": 1},
        "datacenters": {"type": "array", "items": {"type": "string", "minLength": 1}, "default": ["*"]}
      }
    },
    "status": {
      "type": "object",
      "properties": {
        "observedGeneration": {"type": "integer", "minimum": 0},
        "observedSpecHash":   {"type": "string"},
        "conditions": {
          "type": "array",
          "items": {
            "type": "object",
            "required": ["type", "status"],
            "properties": {
              "type":               {"type": "string"},
              "status":             {"enum": ["True", "False", "Unknown"]},
              "reason":             {"type": "string"},
              "message":            {"type": "string"},
              "lastTransitionTime": {"type": "string"}
            }
          }
        },
        "class":     {"type": "string"},
        "addresses": {"type": "array", "items": {"type": "string"}},
        "targets":   {"type": "array", "items": {"type": "string"}},
        "leavingNodes": {"type": "array", "items": {"type": "string"}},
        "resource":  {"type": "string"}
      }
    }
  }
}
EOT

  rule {
    expression = "!has(oldSelf) || self.spec.internal == oldSelf.spec.internal"
    message    = "internal can't be changed; delete and recreate the load balancer."
  }

  columns {
    column "Service" { path = "spec.service" }
    column "Port" { path = "spec.port" }
    column "Class" { path = "status.class" }
    column "Addresses" { path = "status.addresses" }
    column "Ready" { path = "status.conditions[?type=='Ready'].status" }
  }

  # The defaulting and validating webhooks.
  dynamic "webhook" {
    for_each = var.webhook_enabled ? ["default", "validate"] : []
    labels   = [webhook.value]

    content {
      mode           = webhook.value
      url            = "${local.webhook_url}/${webhook.value}"
      ca_cert        = var.webhook_ca_cert == "" ? null : "${trimspace(var.webhook_ca_cert)}\n"
      failure_policy = var.webhook_failure_policy
    }
  }

  limits {
    write_rate                = var.write_rate
    identity_write_rate       = var.identity_write_rate
    max_objects_per_namespace = var.max_objects_per_namespace
    max_watches_per_identity  = var.max_watches_per_identity
  }
}
