# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The operator and the raw_exec driver (review finding JOG-19): what the
# pack refuses with a fail in its job template is the rule raw_exec here.

test "the job keeps off nodes with the raw_exec driver" {
  assert {
    condition     = resource.job.acme.group.acme.task.acme.driver == "exec"
    error_message = "the default driver is exec"
  }

  assert {
    condition = (
      [for c in resource.job.acme.constraint : c.attribute] ==
      [runtime("meta.norca.instance"), runtime("attr.driver.raw_exec")]
    )
    error_message = "the job is kept off the nodes whose attribute driver.raw_exec is set"
  }
}

test "raw_exec without allow_raw_exec_nodes is refused" {
  values = {
    driver = "raw_exec"
  }

  expect_error = "driver = \"raw_exec\" needs allow_raw_exec_nodes = true"
}

test "allow_raw_exec_nodes takes raw_exec and leaves the constraint out" {
  values = {
    driver               = "raw_exec"
    allow_raw_exec_nodes = true
  }

  assert {
    condition     = resource.job.acme.group.acme.task.acme.driver == "raw_exec"
    error_message = "the task runs with raw_exec"
  }

  # One constraint block is left, and a block written once reads as an
  # object.
  assert {
    condition     = resource.job.acme.constraint.attribute == runtime("meta.norca.instance")
    error_message = "only the constraint on the nodes of the node scaling operator is left"
  }
}

# Several instances and leader election (review findings CON-6e, CON-6f,
# CON-6g): the pack runs one instance without it, its policy does not grant
# the lease and its service has the check on /healthz alone; the module
# does the same by default, and more with count, leader_election,
# lease_namespace and http01_settle. The rules of a policy read as the text
# the server gets.

test "one instance runs without leader election by default, as the pack" {
  namespace = "norca-system"

  assert {
    condition     = resource.job.acme.group.acme.count == 1
    error_message = "one instance"
  }

  assert {
    condition     = length(resource.job.acme.group.acme.constraint) == 0
    error_message = "the group has no constraint"
  }

  assert {
    condition = resource.job.acme.group.acme.task.acme.config.args == [
      "-controller", "norca-acme",
      "-interval", "5s",
      "-http01-listen", ":${runtime_env("NORCA_PORT_http01")}",
      "-secret-namespace", "norca-system",
      "-secret-prefix", "norca-acme/",
      "-zone-token-namespace", "norca-system",
      "-zone-ttl", "3m",
      "-zone-allow-http=false",
      "-dns-propagation-check=true",
      "-dns-propagation-timeout", "5m",
      "-retry-base", "1m",
      "-retry-max", "2h",
      "-max-attempts", "8",
      "-log-level", "info",
    ]
    error_message = "the flags are those of the pack: no -leader-election, no -lease-namespace, no -http01-settle"
  }

  # The dynamic block of the check on /readyz makes none: the one check
  # reads as an object.
  assert {
    condition = (
      resource.job.acme.group.acme.service[0].check.path == "/healthz" &&
      resource.job.acme.group.acme.service[0].check.interval == "10s"
    )
    error_message = "the service has the one check of the pack, on /healthz"
  }

  assert {
    condition     = resource.policy.acme.rules == <<-EOT
      namespace "*" {
        object "norca.io/CertificateIssuer" {
          capabilities = ["read", "write-status"]
        }
        object "norca.io/CertificateOrder" {
          capabilities = ["read", "write-status"]
        }
        object "norca.io/DNSZone" {
          capabilities = ["read"]
        }
      }
      namespace "norca-system" {
        secret "norca-acme/*" {
          capabilities = ["read-secret", "write-secret"]
        }
        variables {
          path "providers/*" {
            capabilities = ["read"]
          }
        }
      }
    EOT
    error_message = "the policy is that of the pack: the secrets and the tokens of the zones, no lease"
  }
}

test "several instances run on different nodes with leader election" {
  namespace = "norca-system"

  values = {
    count = 2
  }

  assert {
    condition     = resource.job.acme.group.acme.count == 2
    error_message = "two instances"
  }

  assert {
    condition     = [for c in resource.job.acme.group.acme.constraint : c.operator] == ["distinct_hosts"]
    error_message = "the instances are on different nodes"
  }

  assert {
    condition = resource.job.acme.group.acme.task.acme.config.args == [
      "-controller", "norca-acme",
      "-interval", "5s",
      "-http01-listen", ":${runtime_env("NORCA_PORT_http01")}",
      "-secret-namespace", "norca-system",
      "-secret-prefix", "norca-acme/",
      "-zone-token-namespace", "norca-system",
      "-zone-ttl", "3m",
      "-zone-allow-http=false",
      "-leader-election", "-lease-namespace", "norca-system",
      "-dns-propagation-check=true",
      "-dns-propagation-timeout", "5m",
      "-retry-base", "1m",
      "-retry-max", "2h",
      "-max-attempts", "8",
      "-log-level", "info",
    ]
    error_message = "the operator gets -leader-election and the lease in the namespace of the job"
  }

  # The check of the pack still counts for the deployment; the check on
  # /readyz, which a standby fails, does not (review finding CON-6f).
  assert {
    condition = (
      [for c in resource.job.acme.group.acme.service[0].check : c.path] == ["/healthz", "/readyz"] &&
      [for c in resource.job.acme.group.acme.service[0].check : try(c.on_update, "")] == ["", "ignore"]
    )
    error_message = "the service has a check on /readyz that does not count for the deployment, next to the one on /healthz"
  }

  assert {
    condition = (
      resource.job.acme.group.acme.service[0].check[1].name == "leading" &&
      resource.job.acme.group.acme.service[0].check[1].type == "http" &&
      resource.job.acme.group.acme.service[0].check[1].interval == "5s" &&
      resource.job.acme.group.acme.service[0].check[1].timeout == "2s"
    )
    error_message = "the check on /readyz is an http check every 5s"
  }

  assert {
    condition     = resource.policy.acme.rules == <<-EOT
      namespace "*" {
        object "norca.io/CertificateIssuer" {
          capabilities = ["read", "write-status"]
        }
        object "norca.io/CertificateOrder" {
          capabilities = ["read", "write-status"]
        }
        object "norca.io/DNSZone" {
          capabilities = ["read"]
        }
      }
      namespace "norca-system" {
        secret "norca-acme/*" {
          capabilities = ["read-secret", "write-secret"]
        }
        variables {
          path "providers/*" {
            capabilities = ["read"]
          }
          path "controller-lease/norca-acme" {
            capabilities = ["read", "write"]
          }
        }
      }
    EOT
    error_message = "the policy lets the instances read and write the lease, next to the tokens of the zones"
  }
}

test "the lease and the tokens each in a namespace of their own" {
  namespace = "norca-system"

  values = {
    count                = 2
    lease_namespace      = "leases"
    zone_token_namespace = "dns"
  }

  assert {
    condition = [
      for i, arg in resource.job.acme.group.acme.task.acme.config.args :
      resource.job.acme.group.acme.task.acme.config.args[i + 1] if arg == "-lease-namespace"
    ] == ["leases"]
    error_message = "the operator is told the namespace of the lease"
  }

  assert {
    condition     = resource.policy.acme.rules == <<-EOT
      namespace "*" {
        object "norca.io/CertificateIssuer" {
          capabilities = ["read", "write-status"]
        }
        object "norca.io/CertificateOrder" {
          capabilities = ["read", "write-status"]
        }
        object "norca.io/DNSZone" {
          capabilities = ["read"]
        }
      }
      namespace "norca-system" {
        secret "norca-acme/*" {
          capabilities = ["read-secret", "write-secret"]
        }
      }
      namespace "dns" {
        variables {
          path "providers/*" {
            capabilities = ["read"]
          }
        }
      }
      namespace "leases" {
        variables {
          path "controller-lease/norca-acme" {
            capabilities = ["read", "write"]
          }
        }
      }
    EOT
    error_message = "the lease and the tokens are granted in their own namespaces, the secrets in the namespace of the job"
  }
}

test "the lease and the tokens in one namespace that is not the job's" {
  namespace = "norca-system"

  values = {
    count                = 2
    lease_namespace      = "ops"
    zone_token_namespace = "ops"
  }

  assert {
    condition     = resource.policy.acme.rules == <<-EOT
      namespace "*" {
        object "norca.io/CertificateIssuer" {
          capabilities = ["read", "write-status"]
        }
        object "norca.io/CertificateOrder" {
          capabilities = ["read", "write-status"]
        }
        object "norca.io/DNSZone" {
          capabilities = ["read"]
        }
      }
      namespace "norca-system" {
        secret "norca-acme/*" {
          capabilities = ["read-secret", "write-secret"]
        }
      }
      namespace "ops" {
        variables {
          path "providers/*" {
            capabilities = ["read"]
          }
          path "controller-lease/norca-acme" {
            capabilities = ["read", "write"]
          }
        }
      }
    EOT
    error_message = "one block of the namespace holds the tokens and the lease"
  }
}

test "one instance takes leader election when asked, and the lease is named by the controller" {
  namespace = "norca-system"

  values = {
    leader_election = true
    controller      = "acme-eu"
  }

  assert {
    condition     = resource.job.acme.group.acme.count == 1
    error_message = "one instance"
  }

  assert {
    condition     = length(resource.job.acme.group.acme.constraint) == 0
    error_message = "one instance needs no other node"
  }

  assert {
    condition     = contains(resource.job.acme.group.acme.task.acme.config.args, "-leader-election")
    error_message = "the operator gets -leader-election"
  }

  assert {
    condition     = [for c in resource.job.acme.group.acme.service[0].check : c.path] == ["/healthz", "/readyz"]
    error_message = "the check on /readyz follows leader election, not the number of instances"
  }

  assert {
    condition     = length(regexall("path \"controller-lease/acme-eu\" \\{\\s+capabilities = \\[\"read\", \"write\"\\]", resource.policy.acme.rules)) == 1
    error_message = "the lease is the Variable controller-lease/<controller>"
  }
}

test "several instances without HTTP-01 have no service to check" {
  namespace = "norca-system"

  values = {
    count          = 2
    http01_enabled = false
  }

  assert {
    condition     = length(resource.job.acme.group.acme.service) == 0
    error_message = "no service, so no check"
  }

  assert {
    condition     = contains(resource.job.acme.group.acme.task.acme.config.args, "-leader-election")
    error_message = "the operator gets -leader-election"
  }
}

test "http01_settle is the -http01-settle of the operator" {
  values = {
    http01_settle = "45s"
  }

  assert {
    condition = [
      for i, arg in resource.job.acme.group.acme.task.acme.config.args :
      resource.job.acme.group.acme.task.acme.config.args[i + 1] if arg == "-http01-settle"
    ] == ["45s"]
    error_message = "the operator gets the settle time"
  }

  assert {
    condition     = !contains(resource.job.acme.group.acme.task.acme.config.args, "-leader-election")
    error_message = "the settle time does not turn leader election on"
  }
}
