[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]

[[- /* The secret with the root credentials, as environment variables. */ -]]
[[- define "rustfs.credentials" -]]
[[- $v := vars . ]]
      # The root credentials, from the built-in secret store.
      secret "root" {
        path = [[ $v.secret_path | quote ]]

        env {
          RUSTFS_ACCESS_KEY = "access_key"
          RUSTFS_SECRET_KEY = "secret_key"
        }
      }
[[- end -]]

[[- /* Checks the variables the schema can't express. */ -]]
[[- define "rustfs.validate" -]]
[[- $v := vars . -]]
[[- if and (eq $v.mode "single") $v.nodes -]]
[[- fail "nodes is only used with mode = \"distributed\"" -]]
[[- end -]]
[[- if and $v.console_enabled (eq $v.console_port $v.s3_port) -]]
[[- fail "console_port must differ from s3_port" -]]
[[- end -]]
[[- if and $v.metrics_enabled (hasKey $v.extra_env "RUSTFS_OBS_METRIC_ENDPOINT") -]]
[[- fail "RUSTFS_OBS_METRIC_ENDPOINT is set by metrics_enabled: remove it from extra_env" -]]
[[- end -]]
[[- if and $v.traces_enabled (hasKey $v.extra_env "RUSTFS_OBS_TRACE_ENDPOINT") -]]
[[- fail "RUSTFS_OBS_TRACE_ENDPOINT is set by traces_enabled: remove it from extra_env" -]]
[[- end -]]
[[- end -]]
