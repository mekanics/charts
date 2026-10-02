#!/usr/bin/env bash
# Renders the openclaw Deployment and checks each probe has one handler.
set -euo pipefail

chart="$(cd "$(dirname "$0")/.." && pwd)"

check() {
  local label="$1"
  local manifest="$2"
  python3 - "$label" "$manifest" <<'PY'
import re, sys
label, manifest = sys.argv[1], sys.argv[2]
text = open(manifest).read()
deploy = text.split("\nkind: Deployment\n", 1)
if len(deploy) != 2:
    sys.exit(f"{label}: no Deployment")
body = deploy[1]
expect = {
    "startup": ("httpGet", "exec") if label != "default" else ("exec", "httpGet"),
    "liveness": ("httpGet", "exec") if label != "default" else ("exec", "httpGet"),
    "readiness": ("exec", "httpGet"),
}
for probe, (present, absent) in expect.items():
    match = re.search(rf"^          {probe}Probe:\n(.*?)(?=\n          \S)", body, re.S | re.M)
    if not match:
        sys.exit(f"{label}: missing {probe}Probe")
    block = match.group(1)
    has = lambda key: re.search(rf"^            {key}:", block, re.M) is not None
    if not has(present) or has(absent):
        sys.exit(
            f"{label}: {probe}Probe should have {present} and not {absent}\n{block}"
        )
    print(f"{label}: {probe}Probe has {present}")
PY
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

helm template probe-test "$chart" >"$tmp/default.yaml"
check default "$tmp/default.yaml"

helm template probe-test "$chart" -f "$chart/ci/httpget-probes-values.yaml" >"$tmp/httpget.yaml"
check httpget "$tmp/httpget.yaml"

helm template probe-test "$chart" -f "$chart/ci/httpget-null-exec-values.yaml" >"$tmp/null.yaml"
check null "$tmp/null.yaml"

check_doctor() {
  local label="$1"
  local manifest="$2"
  local expect="$3"
  python3 - "$label" "$manifest" "$expect" <<'PY'
import re, sys
label, manifest, expect = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(manifest).read()
deploy = text.split("\nkind: Deployment\n", 1)
if len(deploy) != 2:
    sys.exit(f"{label}: no Deployment")
present = re.search(r"^        - name: init-doctor$", deploy[1], re.M) is not None
if expect == "present" and not present:
    sys.exit(f"{label}: missing init-doctor")
if expect == "absent" and present:
    sys.exit(f"{label}: unexpected init-doctor")
print(f"{label}: init-doctor {expect}")
PY
}

check_doctor default "$tmp/default.yaml" present

helm template probe-test "$chart" --set doctor.onStart=false >"$tmp/doctor-off.yaml"
check_doctor doctor-off "$tmp/doctor-off.yaml" absent

helm template probe-test "$chart" --set debug.enabled=true >"$tmp/debug.yaml"
check_doctor debug "$tmp/debug.yaml" absent
