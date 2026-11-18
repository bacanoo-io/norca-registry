[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
[[- $watch := $v.namespace ]]
[[- if ne $v.watch_namespace "" ]][[ $watch = $v.watch_namespace ]][[ end ]]
[[- $example := $watch ]]
[[- if eq $watch "*" ]][[ $example = "default" ]][[ end ]]
LoadBalancer operator "[[ $v.job_name ]]" in namespace [[ $v.namespace ]]: [[ $v.count ]] controller instance(s), driver [[ $v.driver ]], proxies with [[ $v.proxy_driver ]]. It reconciles the LoadBalancer objects of [[ if eq $watch "*" ]]every namespace[[ else ]]the namespace [[ $watch ]][[ end ]].

Create a load balancer:
  cat > web-lb.hcl <<EOF
  kind      = "norca.io/LoadBalancer"
  name      = "web"
  namespace = "[[ $example ]]"
  spec {
    service = "web"
    port    = 8080
  }
  EOF
  norca object apply web-lb.hcl
  norca object list norca.io/LoadBalancer -namespace [[ $example ]]
  norca object events norca.io/LoadBalancer web -namespace [[ $example ]]

or mark a service with the norca_lb_class / norca_lb_port meta keys.
[[- if $v.webhook_enabled ]]

Webhooks: [[ $v.webhook_url ]]/default and /validate. The kind's webhooks are
approved when the pack is installed with a management token; otherwise run
  norca object-kind webhook approve norca.io/LoadBalancer default
  norca object-kind webhook approve norca.io/LoadBalancer validate
The webhook task reads its certificate from the Variable nomad/jobs/[[ $v.job_name ]]
of the namespace [[ $v.namespace ]] (items webhook_cert, webhook_key).
[[- end ]]
