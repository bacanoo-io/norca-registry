# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

locals {
  # The ID of the job and the name of its service; empty is the release.
  job   = coalesce(var.job_name, rig.release)
  user  = "${var.uid}:${var.gid}"
  tls   = var.tls_mode != "none"
  setup = length(var.databases) > 0 || var.monitoring_enabled

  # The command of the server: TLS, the rules of pg_hba.conf, the settings.
  args = concat(
    ["postgres"],
    local.tls ? ["-c", "ssl=on", "-c", "ssl_cert_file=/tmp/tls/server.crt", "-c", "ssl_key_file=/tmp/tls/server.key"] : [],
    var.tls_required ? ["-c", "hba_file=/local/pg_hba.conf"] : [],
    flatten([for k, v in var.settings : ["-c", "${k}=${v}"]]),
  )

  # The secrets the tasks of the server read.
  secret_paths = concat(
    [var.superuser_secret_path],
    [for d in var.databases : d.secret_path],
    var.monitoring_enabled ? [var.monitoring_secret_path] : [],
    var.tls_mode == "secret" ? [var.tls_secret_path] : [],
  )

  # Where the certificate and key are: the workload certificate, or the
  # secret.
  tls_src = var.tls_mode == "secret" ? "/secrets/tls" : "/secrets/mtls"

  # The setup script: the roles and databases, then the monitoring role.
  setup_script = join("\n", concat(
    [
      "#!/bin/sh",
      "set -eu",
      "i=0",
      "until pg_isready -q; do",
      "  i=$((i + 1))",
      "  if [ \"$i\" -ge 120 ]; then echo \"PostgreSQL is not ready after 10 minutes\" >&2; exit 1; fi",
      "  sleep 5",
      "done",
      "run() { psql -X -q -v ON_ERROR_STOP=1 \"$@\"; }",
    ],
    flatten([for i, d in var.databases : [
      "PW=\"$DB_${i}_PASSWORD\" run -v role='${d.user}' -f /local/role.sql",
      "run -v role='${d.user}' -v db='${d.name}' -f /local/database.sql",
      "echo \"role ${d.user} and database ${d.name} ready\"",
    ]]),
    var.monitoring_enabled ? [
      "if [ -n \"$${MONITORING_PASSWORD:-}\" ]; then",
      "  PW=\"$MONITORING_PASSWORD\" run -v role='${var.monitoring_user}' -f /local/role.sql",
      "  run -c 'GRANT pg_monitor TO ${var.monitoring_user}'",
      "  echo \"monitoring role ${var.monitoring_user} ready (pg_monitor)\"",
      "else",
      "  echo \"secret ${var.monitoring_secret_path} not found: monitoring role ${var.monitoring_user} skipped\"",
      "fi",
    ] : [],
    [""],
  ))

  # The S3 endpoint of the dumps: dump_storage_endpoint, or the first
  # instance of the service dump_storage_service in the native catalog.
  dump_storage_env = var.dump_storage_endpoint != "" ? "S3_ENDPOINT=${var.dump_storage_endpoint}\n" : join("\n", [
    "{{- range $i, $s := nomadService \"${var.dump_storage_service}\" }}{{ if eq $i 0 }}",
    "S3_ENDPOINT={{ $s.Address }}:{{ $s.Port }}",
    "{{- end }}{{ end }}",
    "",
  ])
}
