# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Services marked for the LoadBalancer operator must name a valid frontend
# port (norca_lb_port).
admission "service-marks" {
  enabled = var.admission_policy_enabled

  name        = "${var.job_name}-service-marks"
  description = "Services marked for the LoadBalancer operator must name a valid frontend port (norca_lb_port)"
  action      = var.admission_policy_action

  match {
    resources  = ["job"]
    namespaces = local.all ? null : [local.watch]
  }

  rule {
    expression = "job.TaskGroups.all(g, (!has(g.Services) || g.Services == null || g.Services.all(s, ${local.port_mark_ok})) && (!has(g.Tasks) || g.Tasks == null || g.Tasks.all(t, !has(t.Services) || t.Services == null || t.Services.all(s, ${local.port_mark_ok}))))"
    message    = "the norca_lb_port meta of a service must be a port number between 1 and 65535"
  }
}
