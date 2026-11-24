# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The LoadBalancer operator: the controller, and with webhook_enabled the
# webhooks of the LoadBalancer kind.
job "controller" {
  id          = var.job_name
  name        = var.job_name
  type        = "service"
  region      = rigger.region
  datacenters = var.datacenters

  # Never on a node with the raw_exec driver (review finding JOG-19): a
  # raw_exec task or alloc-node-exec there runs as the user of the agent and
  # reads the secrets of every allocation of the node, the identity token of
  # this job and its bound ACL policies among them (allow_raw_exec_nodes).
  dynamic "constraint" {
    for_each = var.allow_raw_exec_nodes ? [] : [1]

    content {
      attribute = runtime("attr.driver.raw_exec")
      operator  = "is_not_set"
    }
  }

  group "controller" {
    count = var.count

    network {
      port "metrics" {}

      dynamic "port" {
        for_each = var.webhook_enabled ? ["webhook"] : []
        labels   = [port.value]

        content {
          static = var.webhook_port
        }
      }
    }

    task "controller" {
      driver = var.driver

      config {
        run_for = local.mock ? "87600h" : null
        image   = local.docker ? var.image : null
        ports   = local.docker ? ["metrics"] : null
        command = local.mock || local.docker ? null : var.binary
        args    = local.mock ? null : local.controller_args
      }

      # The CA of the providers' https certificates.
      dynamic "template" {
        for_each = var.class_ca_cert != "" && !local.mock ? [var.class_ca_cert] : []

        content {
          data        = "${trimspace(template.value)}\n"
          destination = "local/class-ca.pem"
          change_mode = "restart"
        }
      }

      # The controller calls the API on the task API socket with its
      # workload identity; the ACL policy of the module is bound to this
      # job.
      identity {
        env = true
      }

      env {
        NORCA_ADDR = "unix://${runtime_env("NORCA_SECRETS_DIR")}/api.sock"
      }

      resources {
        cpu    = var.cpu
        memory = var.memory
      }
    }

    # The defaulting and validating webhooks of the LoadBalancer kind. The
    # certificate and key come from the job's Variable (nomad/jobs/<job>,
    # items webhook_cert and webhook_key).
    dynamic "task" {
      for_each = var.webhook_enabled ? ["webhook"] : []
      labels   = [task.value]

      content {
        driver = var.driver

        config {
          run_for = local.mock ? "87600h" : null
          image   = local.docker ? var.image : null
          ports   = local.docker ? ["webhook"] : null
          command = local.mock || local.docker ? null : var.binary
          args    = local.mock ? null : local.webhook_args
        }

        dynamic "template" {
          for_each = local.mock ? [] : [{ item = "webhook_cert", file = "webhook.pem" }, { item = "webhook_key", file = "webhook-key.pem" }]

          content {
            data        = "{{ with nomadVar \"${local.variable_path}\" }}{{ .${template.value.item} }}{{ end }}"
            destination = "secrets/${template.value.file}"
            change_mode = "restart"
          }
        }

        service {
          name     = "${var.job_name}-webhook"
          port     = "webhook"
          provider = "nomad"
        }

        resources {
          cpu    = 50
          memory = 32
        }
      }
    }
  }
}
