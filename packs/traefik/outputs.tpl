[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
[[- $job := $v.job_name ]][[ if eq $job "" ]][[ $job = (meta "pack.name" .) ]][[ end ]]
Traefik "[[ $job ]]" ([[ if eq $v.job_type "system" ]]on every node[[ else ]][[ $v.count ]] instances on different nodes[[ end ]][[ if ne $v.node_pool "" ]] of the node pool [[ $v.node_pool ]][[ end ]]).

Entrypoints[[ if ne $v.host_network "" ]] (host network [[ $v.host_network ]])[[ end ]]:
[[- range $e := $v.entrypoints ]]
  [[ $e.name ]]: [[ $e.port ]]/[[ $e.protocol ]][[ if ne $e.redirect_to "" ]] -> redirected to [[ $e.redirect_to ]][[ end ]]
[[- end ]]
  traefik (admin): [[ $v.admin_port ]]: /ping[[ if $v.dashboard ]], /dashboard/[[ end ]][[ if $v.metrics ]], /metrics[[ end ]] (keep it closed to the outside)

[[- if gt (len $v.tls_certificates) 0 ]]

Certificates from the secret store (items [[ $v.tls_cert_item ]] and [[ $v.tls_key_item ]]): [[ join ", " $v.tls_certificates ]]
[[- else ]]

No certificate configured: the https entrypoints serve Traefik's self-signed default certificate. Store one and add it to tls_certificates:
  norca secret put traefik/certs/example-com cert=@fullchain.pem key=@privkey.pem
[[- end ]]
[[- if $v.catalog_enabled ]]

Routing a service of the catalog (namespaces [[ join ", " $v.catalog_namespaces ]]):
  service {
    name     = "app"
    port     = "http"
    provider = "nomad"
    tags = [
      "traefik.enable=true",
      "traefik.http.routers.app.rule=Host(`app.example.com`)",
      "traefik.http.routers.app.entrypoints=websecure",
    ]
  }

The workload identity of Traefik reads the services of its own namespace. For the other namespaces bind a policy to the job:
  namespace "*" {
    capabilities = ["read-job"]
  }
  norca acl policy apply -namespace <namespace of the job> -job [[ $job ]] traefik-catalog policy.hcl
[[- end ]]
