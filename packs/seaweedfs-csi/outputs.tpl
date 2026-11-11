[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
[[- $job := $v.job_name ]][[ if eq $job "" ]][[ $job = (meta "pack.name" .) ]][[ end ]]
SeaweedFS CSI job "[[ $job ]]": the plugin "[[ $v.plugin_id ]]" (controller and node) and the mount service on every node, raw_exec; filer [[ if ne $v.filer "" ]][[ $v.filer ]][[ else ]]from the service [[ $v.filer_service ]][[ end ]]; volume statistics every [[ $v.stats_interval ]].

  norca plugin status [[ $v.plugin_id ]]
  norca volume create volume.hcl        # plugin_id = "[[ $v.plugin_id ]]", see the README of the pack
  norca volume status <volume>          # Node Usage: usage and condition reported by the driver
