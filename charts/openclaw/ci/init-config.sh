#!/usr/bin/env bash
# Renders the openclaw Deployment and checks init-config runs as the
# gateway uid and hands the gateway a sticky /tmp. Needs helm and yq v4.
set -euo pipefail

chart="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "$1: $2" >&2
  exit 1
}

render() {
  local out="$1"
  shift
  helm template init-test "$chart" --show-only templates/deployment.yaml "$@" >"$out"
}

q() {
  yq -r "$2" "$1"
}

init='.spec.template.spec.initContainers[] | select(.name == "init-config")'
gateway='.spec.template.spec.containers[] | select(.name == "gateway")'

render "$tmp/default.yaml"
render "$tmp/uid.yaml" --set securityContext.runAsUser=1024 --set securityContext.runAsGroup=100
render "$tmp/no-tmp.yaml" --set tmpDir.enabled=false

for label in default uid; do
  manifest="$tmp/$label.yaml"
  want_uid="$(q "$manifest" "$gateway | .securityContext.runAsUser")"
  want_gid="$(q "$manifest" "$gateway | .securityContext.runAsGroup")"
  got_uid="$(q "$manifest" "$init | .securityContext.runAsUser")"
  got_gid="$(q "$manifest" "$init | .securityContext.runAsGroup")"
  [ "$got_uid:$got_gid" = "$want_uid:$want_gid" ] ||
    fail "$label" "init-config runs as $got_uid:$got_gid, gateway as $want_uid:$want_gid"
  echo "$label: init-config runs as gateway uid $got_uid:$got_gid"
done

manifest="$tmp/default.yaml"
for container in gateway init-doctor; do
  sub="$(q "$manifest" ".spec.template.spec.[\"initContainers\", \"containers\"][] | select(.name == \"$container\") | .volumeMounts[] | select(.mountPath == \"/tmp\") | .subPath")"
  [ "$sub" = "gateway-tmp" ] || fail default "$container mounts /tmp with subPath '$sub', want gateway-tmp"
  echo "default: $container mounts /tmp from gateway-tmp"
done

prep="$(q "$manifest" "$init | .volumeMounts[] | select(.name == \"tmp\") | .mountPath")"
[ "$prep" = "/tmp-volume" ] || fail default "init-config mounts tmp at '$prep', want /tmp-volume"
script="$(q "$manifest" "$init | .command[2]")"
grep -q 'chmod 1777 /tmp-volume/gateway-tmp' <<<"$script" || fail default "init-config does not chmod gateway-tmp to 1777"
grep -q '\[ -k /tmp-volume/gateway-tmp \]' <<<"$script" || fail default "init-config does not verify the sticky bit"
echo "default: init-config prepares a sticky gateway-tmp"

manifest="$tmp/no-tmp.yaml"
[ -z "$(q "$manifest" '.. | select(has("mountPath")) | select(.mountPath == "/tmp" or .mountPath == "/tmp-volume") | .mountPath')" ] ||
  fail no-tmp "tmp is mounted with tmpDir.enabled=false"
! grep -q gateway-tmp <<<"$(q "$manifest" "$init | .command[2]")" ||
  fail no-tmp "init-config prepares gateway-tmp with tmpDir.enabled=false"
echo "no-tmp: no tmp mounts and no gateway-tmp preparation"
