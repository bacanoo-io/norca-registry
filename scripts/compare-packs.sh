#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0
#
# The acceptance check of a converted module (rig design 14): for the
# default values and every example of a pack, the jobs the module renders
# equal the jobs the pack renders, compared as parsed jobs (the JSON of the
# API), not as text.
#
#   packs/<pack>, examples/<pack>/<name>.hcl            the pack and its examples
#   modules/<pack>, modules/<pack>/examples/<name>.vars.hcl  the module and the same examples
#
# An example of the module that the pack has not is given to both: the
# variables keep their names.
#
# Usage: scripts/compare-packs.sh <pack>...
# Environment: NORCA, RIG (the programs, default on the PATH), KEEP (a
#              directory to keep the parsed jobs in).
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
norca="${NORCA:-norca}"
rig="${RIG:-rig}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export NORCA_PACK_CACHE_DIR="$work/cache" NORCA_PACK_CONFIG="$work/config.hcl"
export NORCA_ADDR="http://127.0.0.1:1" GIT_TERMINAL_PROMPT=0

# Variables the default render of a pack needs (see check-packs.sh).
declare -A required=([consul]="--var=consul_license_accepted=true")
declare -A required_module=([consul]="-var=consul_license_accepted=true")

failed=0

compare() { # <pack> <name> <pack var file or ""> <module var file or "">
  local pack="$1" name="$2" pvars="$3" mvars="$4" dir="$work/$1/$2"
  mkdir -p "$dir/pack" "$dir/parsed"
  local pargs=() margs=()
  [ -n "$pvars" ] && pargs+=("--var-file=$pvars")
  [ -n "$mvars" ] && margs+=(-f "$mvars")
  # shellcheck disable=SC2206
  pargs+=(${required[$pack]:-})
  # shellcheck disable=SC2206
  margs+=(${required_module[$pack]:-})

  if ! (cd "$root" && "$norca" pack render "./packs/$pack" --to-dir="$dir/pack" "${pargs[@]}") >"$dir/pack.log" 2>&1; then
    cat "$dir/pack.log"; echo "FAIL: $pack ($name): the pack does not render"; failed=1; return
  fi
  local job
  while IFS= read -r job; do
    if ! "$norca" job run -output "$job" >"$dir/parsed/$(basename "$job").json" 2>"$dir/parse.log"; then
      cat "$dir/parse.log"; echo "FAIL: $pack ($name): $(basename "$job") does not parse"; failed=1; return
    fi
  done < <(find "$dir/pack" -type f -name '*.nomad*' | sort)

  if ! (cd "$root" && "$rig" module render "modules/$pack" -release "$pack" "${margs[@]}") >"$dir/module.json" 2>"$dir/module.log"; then
    cat "$dir/module.log"; echo "FAIL: $pack ($name): the module does not render"; failed=1; return
  fi

  if python3 -I - "$dir" "${KEEP:-}" "$pack-$name" <<'PY'
import json, os, sys

dir, keep, label = sys.argv[1], sys.argv[2], sys.argv[3]

def norm(v):
    """Drops what the two decoders may write differently without meaning:
    nulls, empty lists and objects; the region and namespace of a job,
    which are the release's in a module and variables in a pack."""
    if isinstance(v, dict):
        out = {k: norm(x) for k, x in v.items()}
        return {k: x for k, x in out.items() if x not in (None, [], {})}
    if isinstance(v, list):
        return [norm(x) for x in v]
    return v

pack = {}
for f in sorted(os.listdir(os.path.join(dir, "parsed"))):
    job = json.load(open(os.path.join(dir, "parsed", f)))["Job"]
    pack[job["ID"]] = job
module = {}
for r in json.load(open(os.path.join(dir, "module.json")))["resources"]:
    if r["kind"] == "job":
        module[r["spec"]["ID"]] = r["spec"]

ok = True
for jobs in (pack, module):
    for job in jobs.values():
        job.pop("Region", None)
        job.pop("Namespace", None)
if sorted(pack) != sorted(module):
    print(f"  jobs: pack {sorted(pack)}, module {sorted(module)}")
    ok = False

def diff(a, b, path):
    global ok
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a:
                print(f"  {path}.{k}: only in the module: {json.dumps(b[k])[:200]}"); ok = False
            elif k not in b:
                print(f"  {path}.{k}: only in the pack: {json.dumps(a[k])[:200]}"); ok = False
            else:
                diff(a[k], b[k], f"{path}.{k}")
    elif isinstance(a, list) and isinstance(b, list) and len(a) == len(b):
        for i, (x, y) in enumerate(zip(a, b)):
            diff(x, y, f"{path}[{i}]")
    elif a != b:
        print(f"  {path}: pack {json.dumps(a)[:300]}, module {json.dumps(b)[:300]}"); ok = False

for id in sorted(set(pack) & set(module)):
    diff(norm(pack[id]), norm(module[id]), id)
    if keep:
        os.makedirs(keep, exist_ok=True)
        for side, jobs in (("pack", pack), ("module", module)):
            with open(os.path.join(keep, f"{label}.{id}.{side}.json"), "w") as f:
                json.dump(norm(jobs[id]), f, indent=2, sort_keys=True)
sys.exit(0 if ok else 1)
PY
  then
    echo "ok: $pack ($name)"
  else
    echo "FAIL: $pack ($name): the jobs differ"; failed=1
  fi
}

[ $# -gt 0 ] || { echo "usage: $0 <pack>..." >&2; exit 2; }

for pack in "$@"; do
  compare "$pack" default "" ""
  for ex in "$root/examples/$pack"/*.hcl; do
    [ -f "$ex" ] || continue
    name="$(basename "$ex" .hcl)"
    mex="$root/modules/$pack/examples/$name.vars.hcl"
    if [ ! -f "$mex" ]; then
      echo "FAIL: $pack ($name): modules/$pack/examples/$name.vars.hcl is missing"; failed=1; continue
    fi
    compare "$pack" "$name" "$ex" "$mex"
  done
  # Examples of the module that the pack has not: the same values in both,
  # as the variables keep their names.
  for mex in "$root/modules/$pack/examples"/*.vars.hcl; do
    [ -f "$mex" ] || continue
    name="$(basename "$mex" .vars.hcl)"
    [ -f "$root/examples/$pack/$name.hcl" ] && continue
    compare "$pack" "$name" "$mex" "$mex"
  done
done

exit "$failed"
