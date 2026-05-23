#!/bin/sh
# 10-snap-set.sh — generic chain follower hook for the `drive/drive`
# resource. Translates the v2 driver.* fields broadcast on the
# chain into `snapctl set driver.<key>=<value>` against the
# consuming snap's own config.
#
# Ships from husarion-snap-common. Only relevant for snaps whose
# config schema understands these driver.* keys (rosbot today).
# Leaf snaps without a `drive` cap (e.g. husarion-rplidar) never
# fire this hook even though the file is shipped — the agent
# doesn't run hooks for caps it doesn't load.
#
# Wire vocabulary → snap-config:
#   HUSARION_AGENT_MECANUM              → driver.mecanum
#   HUSARION_AGENT_CONFIGURATION        → driver.configuration
#   HUSARION_AGENT_LED_STRIP            → driver.led-strip
#   HUSARION_AGENT_TF_NAMESPACE_BRIDGE  → driver.tf-namespace-bridge
#
# Each key gets an idempotency check so a no-op chain re-broadcast
# doesn't trigger a snap configure run. configure runs only once
# at the end, only if at least one snapctl set actually changed
# state.
set -eu

LOCKFILE="${SNAP_COMMON}/husarion-agent/.snap-apply-in-flight"
mkdir -p "${SNAP_COMMON}/husarion-agent"
touch "$LOCKFILE"
trap 'setsid sh -c "sleep 60 && rm -f \"$LOCKFILE\"" </dev/null >/dev/null 2>&1 &' EXIT

changed=0
maybe_set() {
    local snap_key="$1"
    local desired="$2"
    [ -z "$desired" ] && return 0
    local current
    current=$(snapctl get "$snap_key" 2>/dev/null || echo "")
    if [ "$current" = "$desired" ]; then
        return 0
    fi
    snapctl set "${snap_key}=${desired}"
    changed=1
}

maybe_set "driver.mecanum"              "${HUSARION_AGENT_MECANUM:-default}"
maybe_set "driver.configuration"        "${HUSARION_AGENT_CONFIGURATION:-}"
maybe_set "driver.led-strip"            "${HUSARION_AGENT_LED_STRIP:-}"
maybe_set "driver.tf-namespace-bridge"  "${HUSARION_AGENT_TF_NAMESPACE_BRIDGE:-}"

if [ "$changed" = "1" ]; then
    "${SNAP}/meta/hooks/configure"
fi
