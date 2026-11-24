#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0
#
# Every job the modules render, for their defaults and every example, passes
# the validation of a Norca server (PUT /v1/validate/job): what the
# decoder of rigger cannot know, the server checks.
#
# Usage: scripts/check-modules-server.sh [module...]   (default: every module)
# Environment: RIGGER (the program, default on the PATH), NORCA_ADDR (the
#              server, default http://127.0.0.1:4646), NORCA_TOKEN,
#              CREATE_NODE_POOLS=1 to create the node pools the jobs name
#              (for a throwaway dev agent).
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
rigger="${RIGGER:-rigger}"
addr="${NORCA_ADDR:-http://127.0.0.1:4646}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Values a module needs to render at all (the installer's decisions).
declare -A required=([consul]="-var=consul_license_accepted=true")

failed=0

check() { # <module dir> <name> [rigger args...]
  local dir="$1" name="$2"; shift 2
  local m; m="$(basename "$dir")"
  if ! "$rigger" module render "$dir" "$@" >"$work/out.json" 2>"$work/err.log"; then
    if [ "$name" = default ] && grep -q 'No value for a variable' "$work/err.log"; then
      echo "skip: $m (default): it has required variables"
      return
    fi
    cat "$work/err.log"; echo "FAIL: $m ($name): does not render"; failed=1; return
  fi
  python3 -I - "$work/out.json" "$addr" "${NORCA_TOKEN:-}" "$m" "$name" "${CREATE_NODE_POOLS:-}" <<'PY' || failed=1
import json, sys, urllib.error, urllib.request
out, addr, token, module, name, create_pools = sys.argv[1:7]
headers = {"X-Nomad-Token": token} if token else {}
ok = True
for r in json.load(open(out))["resources"]:
    if r["kind"] != "job":
        continue
    pool = r["spec"].get("NodePool")
    if create_pools and pool:
        try:
            urllib.request.urlopen(urllib.request.Request(addr + "/v1/node/pool/" + pool, headers=headers))
        except urllib.error.HTTPError as e:
            if e.code != 404:
                raise
            urllib.request.urlopen(urllib.request.Request(addr + "/v1/node/pools", method="PUT", headers=headers,
                                                          data=json.dumps({"Name": pool}).encode()))
    req = urllib.request.Request(addr + "/v1/validate/job", method="PUT",
                                 data=json.dumps({"Job": r["spec"]}).encode(),
                                 headers=headers)
    try:
        res = json.load(urllib.request.urlopen(req))
    except Exception as e:
        print(f"FAIL: {module} ({name}) job {r['name']}: {e}"); ok = False; continue
    if res.get("Error") or res.get("ValidationErrors"):
        print(f"FAIL: {module} ({name}) job {r['name']}: {res.get('Error')} {res.get('ValidationErrors')}"); ok = False
    else:
        print(f"ok: {module} ({name}) job {r['name']}" + (f" (warnings: {res['Warnings']})" if res.get("Warnings") else ""))
sys.exit(0 if ok else 1)
PY
}

dirs=()
if [ $# -gt 0 ]; then
  for m in "$@"; do dirs+=("$root/modules/$m"); done
else
  for d in "$root"/modules/*/; do [ -f "$d/metadata.hcl" ] && dirs+=("${d%/}"); done
fi

for dir in "${dirs[@]}"; do
  m="$(basename "$dir")"
  grep -q 'library *= *true' "$dir/metadata.hcl" && continue
  # shellcheck disable=SC2206
  extra=(${required[$m]:-})
  check "$dir" default "${extra[@]}"
  for ex in "$dir"/examples/*.vars.hcl; do
    [ -f "$ex" ] || continue
    check "$dir" "$(basename "$ex" .vars.hcl)" -f "$ex"
  done
done

exit "$failed"
