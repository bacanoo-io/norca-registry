[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
mTLS gateway "[[ $v.job_name ]]" ([[ $v.job_type ]] job, namespace default[[ if ne $v.region "" ]], region [[ $v.region ]][[ end ]]): service [[ $v.service_name ]] on port [[ $v.port ]] of every [[ if eq $v.job_type "system" ]]eligible node[[ else ]]gateway node ([[ $v.count ]] instances)[[ end ]].
[[- if $v.envoy_task_enabled ]]
Envoy task defined by the pack: [[ $v.envoy_driver ]][[ if has $v.envoy_driver (list "docker" "podman") ]], image [[ if ne $v.envoy_image "" ]][[ $v.envoy_image ]][[ else ]]from the node meta norca.mtls.envoy_*[[ end ]][[ else ]], binary [[ $v.envoy_binary ]][[ end ]].
[[- else ]]
The servers inject the Envoy task mtls-gateway-[[ $v.service_name ]] (image from the node meta norca.mtls.envoy_*).
[[- end ]]

Checks:
  norca job status[[ if ne $v.region "" ]] -region [[ $v.region ]][[ end ]] [[ $v.job_name ]]
  norca service info[[ if ne $v.region "" ]] -region [[ $v.region ]][[ end ]] -verbose [[ $v.service_name ]]

Upstreams in other regions reach the mtls services of this region through it:
  mtls {
    mode = "sidecar"
    upstream "<service>" {
      service    = "<service>"
      region     = "<this region>"
      local_port = 9090
[[- if ne $v.service_name "mtls-gateway" ]]
      gateway    = "[[ $v.service_name ]]"
[[- end ]]
    }
  }

It needs federated servers (server { mtls { federation = true } }), nodes of
the other regions that reach port [[ $v.port ]] of these nodes, and an intention
for every connection in this region (norca service intention create <source> <service>).
