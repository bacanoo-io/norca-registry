# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

locals {
  # The ID of the job and the name of its service; empty is the release.
  job    = coalesce(var.job_name, rigger.release)
  scheme = var.https_enabled ? "https" : "http"
  user   = "${var.uid}:${var.gid}"

  default_port = var.https_enabled ? var.http_port == 443 : var.http_port == 80
  root_url     = var.root_url != "" ? var.root_url : (local.default_port ? "${local.scheme}://${var.domain}/" : "${local.scheme}://${var.domain}:${var.http_port}/")

  metrics_token = var.metrics_enabled && var.metrics_token_secret_path != ""

  # The secrets the tasks of Forgejo read.
  secret_paths = concat(
    [var.keys_secret_path],
    var.admin_enabled ? [var.admin_secret_path] : [],
    var.storage_enabled ? [var.storage_secret_path] : [],
    var.https_enabled ? [var.tls_secret_path] : [],
    local.metrics_token ? [var.metrics_token_secret_path] : [],
  )

  # The keys of Forgejo as files below secrets/, owned by the container user
  # (the client renders them; app.ini only names the files: SECRET_KEY_URI,
  # ...).
  key_files = [for item in ["secret_key", "internal_token", "jwt_secret", "lfs_jwt_secret"] : {
    path = var.keys_secret_path, item = item, file = "secrets/${item}"
  }]

  # The certificate of HTTPS and the bearer token of /metrics, as files.
  tls_files = var.https_enabled ? [
    { path = var.tls_secret_path, item = "cert", file = "secrets/tls.crt" },
    { path = var.tls_secret_path, item = "key", file = "secrets/tls.key" },
  ] : []
  metrics_files = local.metrics_token ? [{ path = var.metrics_token_secret_path, item = "token", file = "secrets/metrics_token" }] : []

  # The S3 endpoint: storage_endpoint, or the first instance of the service
  # storage_service in the native catalog.
  storage_env = var.storage_endpoint != "" ? join("\n", [
    "FORGEJO__storage__MINIO_ENDPOINT=${var.storage_endpoint}",
    "S3_ENDPOINT=${var.storage_endpoint}",
    "",
    ]) : join("\n", [
    "{{- range $i, $s := nomadService \"${var.storage_service}\" }}{{ if eq $i 0 }}",
    "FORGEJO__storage__MINIO_ENDPOINT={{ $s.Address }}:{{ $s.Port }}",
    "S3_ENDPOINT={{ $s.Address }}:{{ $s.Port }}",
    "{{- end }}{{ end }}",
    "",
  ])

  # app.ini settings (FORGEJO__<section>__<KEY>, applied by the image's
  # environment-to-ini at every start). Secrets are not among them.
  env = merge(
    {
      FORGEJO____APP_NAME        = var.app_name
      FORGEJO__server__DOMAIN    = var.domain
      FORGEJO__server__ROOT_URL  = local.root_url
      FORGEJO__server__HTTP_PORT = "3000"
    },
    var.https_enabled ? {
      FORGEJO__server__PROTOCOL  = "https"
      FORGEJO__server__CERT_FILE = "/secrets/tls.crt"
      FORGEJO__server__KEY_FILE  = "/secrets/tls.key"
    } : {},
    var.ssh_enabled ? {
      FORGEJO__server__DISABLE_SSH     = "false"
      FORGEJO__server__SSH_DOMAIN      = var.domain
      FORGEJO__server__SSH_PORT        = tostring(var.ssh_port)
      FORGEJO__server__SSH_LISTEN_PORT = "2222"
      } : {
      FORGEJO__server__DISABLE_SSH      = "true"
      FORGEJO__server__START_SSH_SERVER = "false"
    },
    {
      FORGEJO__server__LFS_START_SERVER      = "true"
      FORGEJO__server__LFS_JWT_SECRET_URI    = "file:/secrets/lfs_jwt_secret"
      FORGEJO__security__INSTALL_LOCK        = "true"
      FORGEJO__security__SECRET_KEY_URI      = "file:/secrets/secret_key"
      FORGEJO__security__INTERNAL_TOKEN_URI  = "file:/secrets/internal_token"
      FORGEJO__oauth2__JWT_SECRET_URI        = "file:/secrets/jwt_secret"
      FORGEJO__database__DB_TYPE             = "sqlite3"
      FORGEJO__service__DISABLE_REGISTRATION = tostring(var.disable_registration)
      FORGEJO__service__REQUIRE_SIGNIN_VIEW  = tostring(var.require_signin_view)
      FORGEJO__packages__ENABLED             = "true"
    },
    var.storage_enabled ? {
      FORGEJO__storage__STORAGE_TYPE        = "minio"
      FORGEJO__storage__MINIO_BUCKET        = var.storage_bucket
      FORGEJO__storage__MINIO_BUCKET_LOOKUP = "path"
      FORGEJO__storage__MINIO_LOCATION      = var.storage_region
      FORGEJO__storage__MINIO_USE_SSL       = tostring(var.storage_use_ssl)
    } : {},
    var.metrics_enabled ? { FORGEJO__metrics__ENABLED = "true" } : {},
    local.metrics_token ? { FORGEJO__metrics__TOKEN__FILE = "/secrets/metrics_token" } : {},
    {
      FORGEJO__log__ROOT_PATH = "/var/lib/gitea/data/log"
      FORGEJO__log__MODE      = "console"
    },
    var.extra_env,
  )
}
