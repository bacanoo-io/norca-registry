# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

output "job" {
  value       = var.job_name
  description = "ID of the controller job; the ACL policy of the same name is bound to it."
}

output "watch_namespace" {
  value       = local.watch
  description = "The namespace of the LoadBalancer objects the controller reconciles; * for every namespace."
}

output "notes" {
  value = join("\n", concat(
    split("\n", <<-EOT
      LoadBalancer operator "${var.job_name}" in namespace ${rigger.namespace}: ${var.count} controller instance(s), driver ${var.driver}, proxies with ${var.proxy_driver}. It reconciles the LoadBalancer objects of ${local.all ? "every namespace" : "the namespace ${local.watch}"}.

      Create a load balancer:
        cat > web-lb.hcl <<EOF
        kind      = "norca.io/LoadBalancer"
        name      = "web"
        namespace = "${local.all ? "default" : local.watch}"
        spec {
          service = "web"
          port    = 8080
        }
        EOF
        norca object apply web-lb.hcl
        norca object list norca.io/LoadBalancer -namespace ${local.all ? "default" : local.watch}
        norca object events norca.io/LoadBalancer web -namespace ${local.all ? "default" : local.watch}

      or mark a service with the norca_lb_class / norca_lb_port meta keys.
    EOT
    ),
    var.webhook_enabled ? split("\n", <<-EOT
      Webhooks: ${var.webhook_url}/default and /validate. The kind's webhooks are
      approved when the module is installed with a management token; otherwise run
        norca object-kind webhook approve norca.io/LoadBalancer default
        norca object-kind webhook approve norca.io/LoadBalancer validate
      The webhook task reads its certificate from the Variable nomad/jobs/${var.job_name}
      of the namespace ${rigger.namespace} (items webhook_cert, webhook_key).
    EOT
    ) : [],
  ))
  description = "How to create a load balancer."
}
