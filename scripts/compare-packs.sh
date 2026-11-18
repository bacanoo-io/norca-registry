#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0
#
# The acceptance check of a converted module (rig design 14): for the
# default values and every example of a pack, the jobs the module renders
# equal the jobs the pack renders, compared as parsed jobs (the JSON of the
# API), not as text; so do its ACL policies, kinds and admission policies.
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

  # The other resources of the pack (ACL policies, kinds, admission
  # policies) are HCL files of the same names as a module's: rendered by rig
  # in a module of their own, both sides pass the same decoder.
  local res packmod="$dir/packmod" found=0
  mkdir -p "$packmod"
  while IFS= read -r res; do
    grep -qvE '^\s*(#.*)?$' "$res" || continue # rendered empty: disabled
    # A module's file is named by the label of its block (design 4.5): the
    # label goes into a name attribute, and the file names the block.
    python3 -I - "$res" "$packmod" <<'PY'
import os, re, sys
src, out = sys.argv[1], sys.argv[2]
base, kind = os.path.basename(src).split(".", 1)
text = open(src).read()
m = re.search(r'^(\w+) "([^"]+)" \{\n', text, re.M)
if m and m.group(2) != base:
    text = text[:m.start()] + f'{m.group(1)} "{base}" {{\n  name = "{m.group(2)}"\n' + text[m.end():]
open(os.path.join(out, base + "." + kind), "w").write(text)
PY
    found=1
  done < <(find "$dir/pack" -type f -name '*.hcl' ! -name '*.nomad*' | sort)
  if [ "$found" = 1 ]; then
    printf 'module {\n  name    = "%s"\n  version = "0.0.0"\n}\n' "$pack" >"$packmod/metadata.hcl"
    if ! "$rig" module render "$packmod" -release "$pack" >"$dir/packres.json" 2>"$dir/packres.log"; then
      cat "$dir/packres.log"; echo "FAIL: $pack ($name): the resources of the pack do not render"; failed=1; return
    fi
  fi

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
others_pack, others_module = {}, {}

def key(r):
    spec = r["spec"] if isinstance(r["spec"], dict) else {}
    return r["kind"] + " " + str(spec.get("Name") or spec.get("name") or spec.get("ID") or spec.get("Path") or r["name"])

for r in json.load(open(os.path.join(dir, "module.json")))["resources"]:
    if r["kind"] == "job":
        module[r["spec"]["ID"]] = r["spec"]
    else:
        others_module[key(r)] = r
if os.path.exists(os.path.join(dir, "packres.json")):
    for r in json.load(open(os.path.join(dir, "packres.json")))["resources"]:
        others_pack[key(r)] = r

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
    elif isinstance(a, str) and isinstance(b, str) and a != b:
        i = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
        start = max(0, i - 60)
        print(f"  {path}: differs at {i}: pack ...{json.dumps(a[start:i + 80])}, module ...{json.dumps(b[start:i + 80])}"); ok = False
    elif a != b:
        print(f"  {path}: pack {json.dumps(a)[:300]}, module {json.dumps(b)[:300]}"); ok = False

# Variables and secrets are new in a module (the pack wrote none, or did
# it with a variable's secret block): only the kinds the pack has are
# compared.
compared = {k for k in others_pack} | {k for k in others_module if k.split(" ")[0] in {"acl-policy", "object-kind", "admission-policy"}}
for k in sorted(compared):
    if k not in others_pack:
        print(f"  {k}: only in the module"); ok = False
    elif k not in others_module:
        print(f"  {k}: only in the pack"); ok = False
    else:
        a, b = others_pack[k], others_module[k]
        diff(norm({"spec": a["spec"], "secret_items": a.get("secret_items")}), norm({"spec": b["spec"], "secret_items": b.get("secret_items")}), k)

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
    echo "FAIL: $pack ($name): the resources differ"; failed=1
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
