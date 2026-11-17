[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
[[- $job := $v.namespace ]]
[[- $tokens := $v.class_token_namespace ]]
[[- $watch := $v.namespace ]]
[[- if ne $v.watch_namespace "" ]][[ $watch = $v.watch_namespace ]][[ end ]]
[[- $all := eq $watch "*" ]]
[[- if $v.acl_policy_enabled ]]
policy [[ printf "%s" $v.job_name | quote ]] {
  description = "Permissions of the LoadBalancer operator (bound to its controller job)"
  rules       = <<EOT
# The namespace of the LoadBalancer objects the controller reconciles[[ if $all ]]: every
# namespace. A block of a namespace by name below takes the place of this
# one for that namespace, so those blocks repeat these rules[[ end ]].
namespace "[[ $watch ]]" {
[[- template "lb.acl.capabilities" . ]]

  variables {
[[- template "lb.acl.proxy_variables" . ]]
[[- if eq $job $watch ]]

    # Leader election leases of the controller instances.
    path "controller-lease/loadbalancer*" {
      capabilities = ["list", "read", "write"]
    }
[[- end ]]
[[- if eq $tokens $watch ]]

    # The tokens of the registered classes.
    path [[ $v.class_token_path | quote ]] {
      capabilities = ["read"]
    }
[[- end ]]
  }
[[- template "lb.acl.objects" . ]]
[[- if $all ]]

  # The registered load balancer classes (cluster-scoped).
  object "norca.io/LoadBalancerClass" {
    capabilities = ["read"]
  }
[[- end ]]
}
[[- if ne $job $watch ]]

# The namespace of the controller job: the leases of its instances.
namespace "[[ $job ]]" {
[[- if $all ]]
[[- template "lb.acl.capabilities" . ]]
[[ end ]]
  variables {
[[- if $all ]]
[[- template "lb.acl.proxy_variables" . ]]
[[ end ]]
    # Leader election leases of the controller instances.
    path "controller-lease/loadbalancer*" {
      capabilities = ["list", "read", "write"]
    }
[[- if eq $tokens $job ]]

    # The tokens of the registered classes.
    path [[ $v.class_token_path | quote ]] {
      capabilities = ["read"]
    }
[[- end ]]
  }
[[- if $all ]]
[[- template "lb.acl.objects" . ]]
[[- end ]]
}
[[- end ]]
[[- if and (ne $tokens $watch) (ne $tokens $job) ]]

# The namespace of the tokens of the registered classes.
namespace "[[ $tokens ]]" {
[[- if $all ]]
[[- template "lb.acl.capabilities" . ]]
[[ end ]]
  variables {
[[- if $all ]]
[[- template "lb.acl.proxy_variables" . ]]
[[ end ]]
    # The tokens of the registered classes.
    path [[ $v.class_token_path | quote ]] {
      capabilities = ["read"]
    }
  }
[[- if $all ]]
[[- template "lb.acl.objects" . ]]
[[- end ]]
}
[[- end ]]
[[- if not $all ]]

# The registered load balancer classes are cluster-scoped: their rule is in
# the namespace "*".
namespace "*" {
  object "norca.io/LoadBalancerClass" {
    capabilities = ["read"]
  }
}
[[- end ]]

# The nodes of the instances: an instance on a node marked as leaving
# (norca.lb.leaving, set by the node scaling operator before a drain) is not
# a target; node events reconcile the load balancers.
node {
  policy = "read"
}
EOT

  job_acl {
    namespace = [[ $v.namespace | quote ]]
    job_id    = [[ $v.job_name | quote ]]
  }
}
[[- end ]]
