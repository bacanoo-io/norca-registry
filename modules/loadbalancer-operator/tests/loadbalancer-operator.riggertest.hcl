# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The controller and the raw_exec driver (review finding JOG-19): the rule
# raw_exec refuses driver = raw_exec without allow_raw_exec_nodes.

test "the job keeps off nodes with the raw_exec driver" {
  assert {
    condition     = resource.job.controller.group.controller.task.controller.driver == "exec"
    error_message = "the default driver is exec"
  }

  assert {
    condition     = [for c in resource.job.controller.constraint : c.attribute] == [runtime("attr.driver.raw_exec")]
    error_message = "the job is kept off the nodes whose attribute driver.raw_exec is set"
  }
}

test "the proxy jobs use exec by default" {
  assert {
    condition = [
      for i, arg in resource.job.controller.group.controller.task.controller.config.args :
      resource.job.controller.group.controller.task.controller.config.args[i + 1] if arg == "-proxy-driver"
    ] == ["exec"]
    error_message = "the controller is told to run the proxy jobs with exec"
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
    condition     = resource.job.controller.group.controller.task.controller.driver == "raw_exec"
    error_message = "the task runs with raw_exec"
  }

  assert {
    condition     = length(resource.job.controller.constraint) == 0
    error_message = "the job has no constraint"
  }
}
