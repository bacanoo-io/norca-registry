#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0
#
# Checks every pack of the registry with a norca binary, without a cluster:
#   - norca pack fmt -check (HCL files and HCL templates),
#   - norca pack render with the default values and with every variable file
#     in examples/<pack>/ (this also checks values.schema.json),
#   - norca job validate of every rendered job (local validation: no agent
#     is contacted).
#
# Usage: scripts/check-packs.sh [pack...]   (default: every pack)
# Environment: NORCA (the norca binary, default "norca" on the PATH),
#              OUT (directory of the rendered jobs, default a temporary one).
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
norca="${NORCA:-norca}"
out="${OUT:-$(mktemp -d)}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# An isolated pack cache and configuration; no agent (local validation).
export NORCA_PACK_CACHE_DIR="$work/cache"
export NORCA_PACK_CONFIG="$work/config.hcl"
export NORCA_ADDR="http://127.0.0.1:1"
export GIT_TERMINAL_PROMPT=0

# Variables the default render needs. Rendering submits nothing: the consul
# pack refuses to render until the Consul license is accepted, which is the
# installer's decision, so the check passes it only to render.
declare -A required=(
  [consul]="--var=consul_license_accepted=true"
)

failed=0
fail() { echo "FAIL: $*"; failed=1; }

check_render() { # <pack> <name> [render args...]
  local pack="$1" name="$2"; shift 2
  local dir="$out/$pack/$name"
  rm -rf -- "${out:?}/${pack:?}/${name:?}"
  mkdir -p "$out/$pack"
  if ! (cd "$root" && "$norca" pack render "./packs/$pack" --to-dir="$dir" --render-output-template "$@") >"$dir.log" 2>&1; then
    cat "$dir.log"
    fail "render $pack ($name)"
    return
  fi
  echo "ok: render $pack ($name)"
  local job res
  while IFS= read -r job; do
    if res="$("$norca" job validate "$job" 2>&1)"; then
      echo "ok: validate $pack ($name) $(basename "$job")"
    elif grep -q 'mode = "gateway"' "$job" && ! grep -qE '^\s*task "' "$job" &&
      [ "$(grep -cE '^\s*\* ' <<<"$res")" = 2 ] && grep -q 'Missing tasks for task group' <<<"$res"; then
      # A gateway group without a task: the servers inject the Envoy task at
      # registration, which local validation can't do.
      echo "ok: validate $pack ($name) $(basename "$job") (Envoy task injected by the servers)"
    else
      echo "$res"
      fail "validate $pack ($name) $(basename "$job")"
    fi
  done < <(find "$dir" -name '*.nomad' | sort)
}

if [ "$#" -gt 0 ]; then
  packs=("$@")
else
  packs=()
  for d in "$root"/packs/*/; do packs+=("$(basename "$d")"); done
fi

"$norca" version | head -n 1
for pack in "${packs[@]}"; do
  [ -f "$root/packs/$pack/metadata.hcl" ] || { fail "no pack $pack"; continue; }
  if (cd "$root" && "$norca" pack fmt -check -recursive "./packs/$pack"); then
    echo "ok: fmt $pack"
  else
    fail "fmt $pack (run: norca pack fmt -recursive ./packs/$pack)"
  fi
  # shellcheck disable=SC2086 # the required arguments are split on purpose
  check_render "$pack" default ${required[$pack]:-}
  for f in "$root/examples/$pack"/*.hcl; do
    [ -f "$f" ] || continue
    # shellcheck disable=SC2086
    check_render "$pack" "$(basename "$f" .hcl)" ${required[$pack]:-} -f "$f"
  done
done

echo "rendered jobs: $out"
if [ "$failed" -ne 0 ]; then
  echo "some checks failed"
  exit 1
fi
echo "all checks passed"
