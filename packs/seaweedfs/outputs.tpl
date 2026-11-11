[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
[[- $job := $v.job_name ]][[ if eq $job "" ]][[ $job = (meta "pack.name" .) ]][[ end ]]
SeaweedFS job "[[ $job ]]": one server (master, volume server, filer) with raw_exec, data in [[ $v.data_dir ]][[ if ne $v.node "" ]] of [[ $v.node ]][[ end ]].

Services (native discovery):
  [[ $job ]]-master    http :[[ $v.master_port ]]   curl http://<addr>/cluster/status
  [[ $job ]]-volume    http :[[ $v.volume_port ]]   curl http://<addr>/status
  [[ $job ]]-filer     http :[[ $v.filer_port ]]   the filer of the seaweedfs-csi pack (filer_service = "[[ $job ]]-filer")
