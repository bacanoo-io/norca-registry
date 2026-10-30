[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]

[[- /* Checks the entrypoints, which the schema checks only one by one. */ -]]
[[- define "traefik.validate" -]]
[[- $v := vars . -]]
[[- $names := dict -]]
[[- $ports := dict -]]
[[- $https := dict -]]
[[- range $e := $v.entrypoints ]][[ if eq $e.protocol "https" ]][[ $_ := set $https $e.name true ]][[ end ]][[ end -]]
[[- range $e := $v.entrypoints -]]
[[- if not (regexMatch "^[A-Za-z0-9][A-Za-z0-9_-]{0,30}$" $e.name) ]][[ fail (printf "entrypoint name %q: letters, digits, - and _, at most 31 characters" $e.name) ]][[ end -]]
[[- if eq $e.name "traefik" ]][[ fail "the entrypoint name \"traefik\" is the admin entrypoint (admin_port)" ]][[ end -]]
[[- if hasKey $names $e.name ]][[ fail (printf "entrypoint %q is defined twice" $e.name) ]][[ end -]]
[[- $_ := set $names $e.name true -]]
[[- /* Nomad reserves a static port for TCP and UDP alike. */ -]]
[[- $port := printf "%v" $e.port -]]
[[- if or (lt (float64 $e.port) 1.0) (gt (float64 $e.port) 65535.0) ]][[ fail (printf "entrypoint %q: port %v is not 1-65535" $e.name $e.port) ]][[ end -]]
[[- if hasKey $ports $port ]][[ fail (printf "entrypoint %q: port %s is used twice" $e.name $port) ]][[ end -]]
[[- $_ := set $ports $port true -]]
[[- if eq (float64 $e.port) (float64 $v.admin_port) ]][[ fail (printf "entrypoint %q: port %v is the admin_port" $e.name $e.port) ]][[ end -]]
[[- if ne $e.redirect_to "" -]]
[[- if ne $e.protocol "http" ]][[ fail (printf "entrypoint %q: redirect_to is for http entrypoints" $e.name) ]][[ end -]]
[[- if not (hasKey $https $e.redirect_to) ]][[ fail (printf "entrypoint %q: redirect_to %q is not an https entrypoint" $e.name $e.redirect_to) ]][[ end -]]
[[- end -]]
[[- end -]]
[[- end -]]

[[- /* A certificate of the secret store (items tls_cert_item and
tls_key_item) as the PEM content of certFile and keyFile in the YAML of the
dynamic configuration; Traefik takes the content as well as a path. The
arguments: the variables, the path of the secret, the text before certFile
(e.g. "    - "), the text before keyFile and the indentation of the PEM
lines. A missing secret fails the template, so the allocation does not
start with a wrong certificate. */ -]]
[[- define "traefik.certificate" -]]
[[- $v := index . 0 ]][[ $path := index . 1 ]][[ $first := index . 2 ]][[ $next := index . 3 ]][[ $pem := index . 4 -]]
[[ $first ]]certFile: |
{{ with nomadSecret [[ $path | quote ]] }}{{ index . [[ $v.tls_cert_item | quote ]] | trimSpace | indent [[ $pem ]] }}{{ else }}{{ sprig_fail "the secret [[ $path ]] does not exist" }}{{ end }}
[[ $next ]]keyFile: |
{{ with nomadSecret [[ $path | quote ]] }}{{ index . [[ $v.tls_key_item | quote ]] | trimSpace | indent [[ $pem ]] }}{{ end }}
[[- end -]]
