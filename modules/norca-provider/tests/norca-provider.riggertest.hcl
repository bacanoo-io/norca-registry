# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The provider and the raw_exec driver (review finding JOG-19): what the
# pack refuses with a fail in its job template is the rule raw_exec here.

test "the job keeps off nodes with the raw_exec driver" {
  assert {
    condition     = resource.job.provider.group.provider.task.provider.driver == "exec"
    error_message = "the default driver is exec"
  }

  assert {
    condition = (
      [for c in resource.job.provider.constraint : c.attribute] ==
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

# The docker platform of norca-provider calls the docker CLI of its host.
test "allow_raw_exec_nodes takes raw_exec and leaves the constraint out" {
  values = {
    driver               = "raw_exec"
    allow_raw_exec_nodes = true
  }

  assert {
    condition     = resource.job.provider.group.provider.task.provider.driver == "raw_exec"
    error_message = "the task runs with raw_exec"
  }

  # One constraint block is left, and a block written once reads as an
  # object.
  assert {
    condition     = resource.job.provider.constraint.attribute == runtime("meta.norca.instance")
    error_message = "only the constraint on the nodes of the node scaling operator is left"
  }
}

test "a single named datacenter is refused" {
  values = {
    datacenters = ["dc1"]
  }

  expect_error = "datacenters names only one datacenter"
}
