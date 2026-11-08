[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
norca-provider "[[ $v.job_name ]]" in namespace [[ $v.namespace ]]: driver [[ $v.driver ]], port [[ $v.port ]].

It registers a norca.io/NodeProvider object for every provider with a node
section and a norca.io/LoadBalancerClass object for every class:
  norca object list norca.io/NodeProvider
  norca object list norca.io/LoadBalancerClass
[[- if $v.secrets ]]

The secrets of the providers come from the Variable nomad/jobs/[[ $v.job_name ]]
(each item is an environment variable of the task, for env:NAME):
  norca var put -namespace [[ $v.namespace ]] nomad/jobs/[[ $v.job_name ]] PROVIDER_TOKEN=... HCLOUD_TOKEN=...
[[- end ]]

The operators read the token of a provider from its token_variable (item
token), with the same value as the provider's own token:
  norca var put providers/<name> token=...
