# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The operator and the raw_exec driver (review finding JOG-19): the rule
# raw_exec refuses driver = raw_exec without allow_raw_exec_nodes.

test "the job keeps off nodes with the raw_exec driver" {
  assert {
    condition     = resource.job.dns.group.dns.task.dns.driver == "exec"
    error_message = "the default driver is exec"
  }

  assert {
    condition = (
      [for c in resource.job.dns.constraint : c.attribute] ==
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
    condition     = resource.job.dns.group.dns.task.dns.driver == "raw_exec"
    error_message = "the task runs with raw_exec"
  }

  # One constraint block is left, and a block written once reads as an
  # object.
  assert {
    condition     = resource.job.dns.constraint.attribute == runtime("meta.norca.instance")
    error_message = "only the constraint on the nodes of the node scaling operator is left"
  }
}

# Several instances and leader election (review finding CON-6e): by
# default one instance runs without it and its policy does not grant the
# lease; count and leader_election do more.
# The rules of a policy read as the text the server gets.

test "one instance runs without leader election by default" {
  namespace = "norca-system"

  assert {
    condition     = resource.job.dns.group.dns.count == 1
    error_message = "one instance"
  }

  assert {
    condition     = length(resource.job.dns.group.dns.constraint) == 0
    error_message = "the group has no constraint"
  }

  assert {
    condition = resource.job.dns.group.dns.task.dns.config.args == [
      "-requeue", "5m",
      "-zone-token-namespace", "norca-system",
      "-zone-ttl", "3m",
      "-zone-allow-http=false",
      "-log-level", "info",
    ]
    error_message = "the flags are those of one instance: no -leader-election, no -lease-namespace"
  }

  assert {
    condition     = resource.policy.dns.rules == <<-EOT
      namespace "*" {
        capabilities = ["read-job"]
        object "norca.io/DNSRecord" {
          capabilities = ["read", "write-status", "write-events", "manage-finalizers"]
        }
        object "norca.io/LoadBalancer" {
          capabilities = ["read"]
        }
        object "norca.io/DNSZone" {
          capabilities = ["read"]
        }
      }
      namespace "norca-system" {
        capabilities = ["list-jobs"]
        variables {
          path "providers/*" {
            capabilities = ["read"]
          }
        }
      }
    EOT
    error_message = "the policy is that of one instance: the tokens of the zones, no lease"
  }
}

test "several instances run on different nodes with leader election" {
  namespace = "norca-system"

  values = {
    count = 2
  }

  assert {
    condition     = resource.job.dns.group.dns.count == 2
    error_message = "two instances"
  }

  assert {
    condition     = [for c in resource.job.dns.group.dns.constraint : c.operator] == ["distinct_hosts"]
    error_message = "the instances are on different nodes"
  }

  assert {
    condition = resource.job.dns.group.dns.task.dns.config.args == [
      "-requeue", "5m",
      "-zone-token-namespace", "norca-system",
      "-zone-ttl", "3m",
      "-zone-allow-http=false",
      "-leader-election", "-lease-namespace", "norca-system",
      "-log-level", "info",
    ]
    error_message = "the operator gets -leader-election and the lease in the namespace of the job"
  }

  assert {
    condition     = resource.policy.dns.rules == <<-EOT
      namespace "*" {
        capabilities = ["read-job"]
        object "norca.io/DNSRecord" {
          capabilities = ["read", "write-status", "write-events", "manage-finalizers"]
        }
        object "norca.io/LoadBalancer" {
          capabilities = ["read"]
        }
        object "norca.io/DNSZone" {
          capabilities = ["read"]
        }
      }
      namespace "norca-system" {
        capabilities = ["list-jobs"]
        variables {
          path "providers/*" {
            capabilities = ["read"]
          }
          path "controller-lease/norca-dns" {
            capabilities = ["read", "write"]
          }
        }
      }
    EOT
    error_message = "the policy lets the instances read and write the lease, next to the tokens of the zones"
  }
}

test "the lease stays in the namespace of the job when the tokens are in another" {
  namespace = "norca-system"

  values = {
    count                = 3
    zone_token_namespace = "dns"
  }

  assert {
    condition = resource.job.dns.group.dns.task.dns.config.args == [
      "-requeue", "5m",
      "-zone-token-namespace", "dns",
      "-zone-ttl", "3m",
      "-zone-allow-http=false",
      "-leader-election", "-lease-namespace", "norca-system",
      "-log-level", "info",
    ]
    error_message = "the lease is in the namespace of the job, the tokens in theirs"
  }

  # The namespace of the job has a block of its own, with a capability: its
  # block takes the place of the "*" block.
  assert {
    condition     = resource.policy.dns.rules == <<-EOT
      namespace "*" {
        capabilities = ["read-job"]
        object "norca.io/DNSRecord" {
          capabilities = ["read", "write-status", "write-events", "manage-finalizers"]
        }
        object "norca.io/LoadBalancer" {
          capabilities = ["read"]
        }
        object "norca.io/DNSZone" {
          capabilities = ["read"]
        }
      }
      namespace "dns" {
        capabilities = ["list-jobs"]
        variables {
          path "providers/*" {
            capabilities = ["read"]
          }
        }
      }
      namespace "norca-system" {
        capabilities = ["list-jobs"]
        variables {
          path "controller-lease/norca-dns" {
            capabilities = ["read", "write"]
          }
        }
      }
    EOT
    error_message = "the lease is granted in the namespace of the job, the tokens in theirs"
  }
}

test "one instance takes leader election when asked" {
  namespace = "norca-system"

  values = {
    leader_election = true
  }

  assert {
    condition     = resource.job.dns.group.dns.count == 1
    error_message = "one instance"
  }

  assert {
    condition     = length(resource.job.dns.group.dns.constraint) == 0
    error_message = "one instance needs no other node"
  }

  assert {
    condition     = contains(resource.job.dns.group.dns.task.dns.config.args, "-leader-election")
    error_message = "the operator gets -leader-election"
  }

  assert {
    condition     = length(regexall("path \"controller-lease/norca-dns\" \\{\\s+capabilities = \\[\"read\", \"write\"\\]", resource.policy.dns.rules)) == 1
    error_message = "the policy lets the instance read and write the lease"
  }
}
