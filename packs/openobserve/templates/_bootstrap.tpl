[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]

[[- /* The bootstrap task: organizations, the ingest service account and its
credentials in the secret store, the S3 bucket (cluster). It talks to the
OpenObserve instance of its own allocation. */ -]]
[[- define "oo.bootstrap" -]]
[[- $v := vars . ]]
[[- if $v.bootstrap_enabled ]]
[[- $job := $v.job_name ]][[ if eq $job "" ]][[ $job = (meta "pack.name" .) ]][[ end ]]
[[- $cluster := eq $v.mode "cluster" ]]
[[- $bucket := and $cluster $v.s3_create_bucket ]]

    # Idempotent setup after every start of the instance: the organizations,
    # the service account of the collectors and its token in the secret store
    # ([[ $v.ingest_secret_path ]])[[ if $bucket ]], the S3 bucket[[ end ]]. The token is rotated only when the
    # stored credentials don't work (first run, or a lost secret).
    task "bootstrap" {
      driver = "docker"

      lifecycle {
        hook    = "poststart"
        sidecar = false
      }

      config {
        image      = [[ $v.bootstrap_image | quote ]]
        entrypoint = ["/bin/sh", "/local/bootstrap.sh"]
      }

      # NOMAD_TOKEN: the workload identity, which writes the ingest secret
      # through the task API (ACL policy of the pack).
      identity {
        env = true
      }

      secret "root" {
        path = [[ $v.root_secret_path | quote ]]

        env {
          ROOT_PASSWORD = "password"
        }
      }

      # The stored ingest credentials, if any.
      secret "ingest" {
        path     = [[ $v.ingest_secret_path | quote ]]
        optional = true
        timeout  = "10s"

        env {
          INGEST_USERNAME = "username"
          INGEST_PASSWORD = "password"
        }
      }
[[- if $bucket ]]

      secret "s3" {
        path = [[ $v.s3_secret_path | quote ]]

        env {
          AWS_ACCESS_KEY_ID     = "access_key"
          AWS_SECRET_ACCESS_KEY = "secret_key"
        }
      }

      template {
        destination = "secrets/s3.env"
        env         = true
        data        = <<-EOF
[[- if ne $v.s3_endpoint "" ]]
          S3_URL=[[ $v.s3_endpoint ]]
[[- else ]]
          {{- range $i, $s := nomadService "[[ $v.s3_service ]]" }}{{ if eq $i 0 }}
          S3_URL=[[ if $v.s3_use_ssl ]]https[[ else ]]http[[ end ]]://{{ $s.Address }}:{{ $s.Port }}
          {{- end }}{{ end }}
[[- end ]]
        EOF
      }
[[- end ]]

      env {
        ROOT_EMAIL     = [[ $v.root_email | quote ]]
        OO_IP          = "${NOMAD_IP_http}"
        OO_PORT        = "${NOMAD_HOST_PORT_http}"
        OO_NAME        = "[[ $job ]].service.${NOMAD_NAMESPACE}.nomad"
        ORGANIZATIONS  = [[ join " " $v.organizations | quote ]]
        INGEST_ORG     = [[ $v.ingest_organization | quote ]]
        INGEST_ACCOUNT = [[ $v.ingest_service_account | quote ]]
        INGEST_PATH    = [[ $v.ingest_secret_path | quote ]]
      }

      template {
        destination = "local/bootstrap.sh"
        data        = <<-EOF
          #!/bin/sh
          set -u
          log() { echo "bootstrap: $*"; }
[[- if eq $v.tls_mode "mtls" ]]
          # The instance's workload certificate names the service, not the
          # address: connect by name, verified with the trust bundle.
          base="https://$OO_NAME:$OO_PORT"
          oocurl() { curl -sS --cacert "$NOMAD_SECRETS_DIR/mtls/bundle.pem" --resolve "$OO_NAME:$OO_PORT:$OO_IP" "$@"; }
[[- else if eq $v.tls_mode "secret" ]]
          # The certificate of the secret need not name the node address; the
          # connection stays on the node.
          base="https://$OO_IP:$OO_PORT"
          oocurl() { curl -sS -k "$@"; }
[[- else ]]
          base="http://$OO_IP:$OO_PORT"
          oocurl() { curl -sS "$@"; }
[[- end ]]
          # api <user:password> <method> <path> [json]: the body goes to
          # /tmp/body, the HTTP status code to stdout.
          api() {
            if [ $# -ge 4 ]; then
              oocurl -o /tmp/body -w '%%{http_code}' -u "$1" -X "$2" -H 'Content-Type: application/json' --data "$4" "$base$3"
            else
              oocurl -o /tmp/body -w '%%{http_code}' -u "$1" -X "$2" "$base$3"
            fi
          }
          root="$ROOT_EMAIL:$ROOT_PASSWORD"

          i=0
          until [ "$(oocurl -o /dev/null -w '%%{http_code}' "$base/healthz" 2>/dev/null)" = 200 ]; do
            i=$((i + 1))
            if [ "$i" -ge 120 ]; then log "OpenObserve is not ready after 10 minutes"; exit 1; fi
            sleep 5
          done
[[- if $bucket ]]

          # The S3 bucket (S3 CreateBucket signed with AWS SigV4).
          code=$(curl -sS -o /tmp/s3 -w '%%{http_code}' -X PUT --aws-sigv4 "aws:amz:[[ $v.s3_region ]]:s3" \
            --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" "$S3_URL/[[ $v.s3_bucket ]]")
          case "$code" in
            200) log "bucket [[ $v.s3_bucket ]] created" ;;
            409) log "bucket [[ $v.s3_bucket ]] exists" ;;
            *) log "bucket [[ $v.s3_bucket ]]: HTTP $code"; cat /tmp/s3; exit 1 ;;
          esac
[[- end ]]

          # Organizations: "default" comes with the root user; another one is
          # created by a first ingestion (the API would give it a random
          # identifier).
          code=$(api "$root" GET /api/organizations)
          [ "$code" = 200 ] || { log "listing the organizations: HTTP $code"; cat /tmp/body; exit 1; }
          cp /tmp/body /tmp/orgs
          for org in $ORGANIZATIONS; do
            if grep -q "\"identifier\":\"$org\"" /tmp/orgs; then
              log "organization $org exists"
              continue
            fi
            code=$(api "$root" POST "/api/$org/norca_bootstrap/_json" '[{"message":"organization created by the Norca openobserve pack"}]')
            [ "$code" = 200 ] || { log "creating organization $org: HTTP $code"; cat /tmp/body; exit 1; }
            log "organization $org created"
          done

          # The ingest credentials in the secret store still work: done.
          if [ -n "$${INGEST_USERNAME:-}" ] && [ -n "$${INGEST_PASSWORD:-}" ]; then
            code=$(api "$INGEST_USERNAME:$INGEST_PASSWORD" GET "/api/$INGEST_ORG/streams")
            if [ "$code" = 200 ]; then
              log "the ingest credentials in $INGEST_PATH work"
              exit 0
            fi
            log "the ingest credentials in $INGEST_PATH don't work (HTTP $code): new token"
          fi

          # The service account (an existing one is kept) and a new token.
          code=$(api "$root" POST "/api/$INGEST_ORG/service_accounts" \
            "{\"email\":\"$INGEST_ACCOUNT\",\"first_name\":\"otel\",\"last_name\":\"collector\"}")
          log "service account $INGEST_ACCOUNT: HTTP $code (an existing account answers with an error)"
          code=$(api "$root" PUT "/api/$INGEST_ORG/service_accounts/$INGEST_ACCOUNT?rotateToken=true" '{}')
          [ "$code" = 200 ] || { log "token of $INGEST_ACCOUNT: HTTP $code"; cat /tmp/body; exit 1; }
          token=$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' /tmp/body)
          rm -f /tmp/body
          [ -n "$token" ] || { log "no token in the response"; exit 1; }

          # Into the secret store, through the task API with the workload
          # identity of this task.
          code=$(curl -sS -o /tmp/put -w '%%{http_code}' --unix-socket "$NOMAD_SECRETS_DIR/api.sock" -X PUT \
            -H "X-Nomad-Token: $NOMAD_TOKEN" \
            --data "{\"Items\":{\"username\":\"$INGEST_ACCOUNT\",\"password\":\"$token\",\"organization\":\"$INGEST_ORG\"}}" \
            "http://localhost/v1/secret/$INGEST_PATH?namespace=$NOMAD_NAMESPACE")
          token=""
          if [ "$code" != 200 ]; then
            log "writing $INGEST_PATH failed: HTTP $code $(cat /tmp/put)"
            log "bind the ACL policy of the pack (acl_policy_enabled), or rotate the token by hand and store it:"
            log "  curl -u <root> -X PUT -H 'Content-Type: application/json' --data '{}' $base/api/$INGEST_ORG/service_accounts/$INGEST_ACCOUNT?rotateToken=true"
            log "  norca secret put -namespace $NOMAD_NAMESPACE $INGEST_PATH username=$INGEST_ACCOUNT organization=$INGEST_ORG password=-"
            exit 1
          fi
          log "ingest credentials of $INGEST_ACCOUNT stored in $INGEST_PATH"
        EOF
      }

      restart {
        attempts = 3
        delay    = "30s"
        mode     = "fail"
      }

      resources {
        cpu    = 50
        memory = 32
      }
    }
[[- end ]]
[[- end -]]
