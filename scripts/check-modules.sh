#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0
#
# The checks of the registry (rigger design 7.4), with the rigger program on the
# PATH (RIGGER overrides it): the files are formatted, and every module loads,
# validates, renders its examples and passes its tests.
set -euo pipefail

rigger="${RIGGER:-rigger}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

"$rigger" fmt -check modules

for dir in modules/*/ modules/lib/*/; do
  [ -f "$dir/metadata.hcl" ] || continue
  "$rigger" module validate "$dir"
  if [ -d "$dir/tests" ]; then
    "$rigger" module test "$dir"
  fi
done
