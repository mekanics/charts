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
