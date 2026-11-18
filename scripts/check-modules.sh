#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0
#
# The checks of the registry (rig design 7.4), with the rig program on the
# PATH (RIG overrides it): the files are formatted, and every module loads,
# validates, renders its examples and passes its tests.
set -euo pipefail

rig="${RIG:-rig}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

"$rig" fmt -check modules

for dir in modules/*/ modules/lib/*/; do
  [ -f "$dir/metadata.hcl" ] || continue
  "$rig" module validate "$dir"
  if [ -d "$dir/tests" ]; then
    "$rig" module test "$dir"
  fi
done
