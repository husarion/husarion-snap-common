#!/bin/sh
# configure-snap-to-files.sh — reverse bridge: snap `ros.*` -> files-first config.
#
# Run from a consumer snap's `configure` hook, AFTER configure_hook_ros.sh has
# resolved ros.env. On a node that OWNS the network concern (role: source /
# does NOT follow `network` from an upstream) it pushes the just-set ROS config
# into the files-first config, so the husarion-agent propagates it to downstream
# followers. Without it, `snap set <snap> ros.*` would only touch this node's
# local ros.env and never reach the chain (self-contained rosbot -> rplidar).
#
# Self-gating + loop-safe:
#   * no-op unless the agent socket is up, `curl` is present, and this node
#     owns the network concern (its follow.yaml does not pull `network`);
#   * only PUTs fields that DIFFER from the published shared.env, so it does not
#     ping-pong with the forward hook (config-seed/hooks/network), which writes
#     snap config FROM these same files. The two converge in one round.
set -eu

STATE_DIR="${SNAP_COMMON}/husarion-agent"
SOCK="${STATE_DIR}/agent.sock"
FOLLOW="${STATE_DIR}/follow.yaml"
SHARED="${STATE_DIR}/config/network/shared.env"
ROS_ENV="${SNAP_COMMON}/ros.env"

# Agent not up yet (first configure during install), or no curl -> nothing to do.
[ -S "$SOCK" ] || exit 0
command -v curl >/dev/null 2>&1 || exit 0

# Ownership gate: if we follow `network` from an upstream, the upstream is the
# source of truth — never push our local snap config up the chain.
if [ -f "$FOLLOW" ] && grep -q 'network' "$FOLLOW" 2>/dev/null; then
    exit 0
fi

cur() { grep -E "^$1=" "$SHARED" 2>/dev/null | tail -1 | cut -d= -f2- || true; }

# Desired shared values: domain / namespace / discovery from the snap config;
# the resolved RMW implementation from the ros.env that configure_hook_ros.sh
# just wrote (reuse its transport->RMW resolution rather than re-deriving it).
DOMAIN="$(snapctl get ros.domain-id 2>/dev/null || true)"
NAMESPACE="$(snapctl get ros.namespace 2>/dev/null || true)"
DISCOVERY="$(snapctl get ros.automatic-discovery-range 2>/dev/null | tr 'a-z' 'A-Z' || true)"
RMW="$(grep -E '^export RMW_IMPLEMENTATION=' "$ROS_ENV" 2>/dev/null | tail -1 | cut -d= -f2 || true)"

# RMW_PROFILE is the profile half of the `ros.transport` token (the DDS/zenoh
# config name). It is SHARED so a `zenoh/shm` selection on the source reaches
# followers intact — without it the forward hook re-derives transport from RMW
# + an empty profile and collapses `zenoh/shm` back to `rmw_zenoh_cpp`. Parse it
# the same way configure_hook_ros.sh does (kind/profile, bare impl = none, plus
# the legacy fastdds/cyclonedds aliases).
TRANSPORT="$(snapctl get ros.transport 2>/dev/null || true)"
case "$TRANSPORT" in
    */*)            PROFILE="${TRANSPORT#*/}" ;;
    rmw_*)          PROFILE="" ;;
    udp|shm|udp-lo) PROFILE="$TRANSPORT" ;;
    udp-lo-cyclone) PROFILE="udp-lo" ;;
    *)              PROFILE="" ;;
esac

fields=""
add() {  # KEY VALUE — non-empty only (empty = "leave unchanged")
    [ -n "$2" ] || return 0
    [ "$(cur "$1")" = "$2" ] && return 0
    fields="${fields}${fields:+,}\"$1\":\"$2\""
}
add_clearable() {  # KEY VALUE — empty allowed (e.g. clearing a profile)
    [ "$(cur "$1")" = "$2" ] && return 0
    fields="${fields}${fields:+,}\"$1\":\"$2\""
}
add ROS_DOMAIN_ID "$DOMAIN"
add ROS_NAMESPACE "$NAMESPACE"
add ROS_AUTOMATIC_DISCOVERY_RANGE "$DISCOVERY"
add RMW_IMPLEMENTATION "$RMW"
add_clearable RMW_PROFILE "$PROFILE"

[ -n "$fields" ] || exit 0

echo "configure-snap-to-files.sh: owner node — scheduling chain propagation of snap ros.* ({${fields}})"
# Defer + detach the PUT. This script runs inside the snap's `configure` hook,
# which holds snapd's per-snap lock. The agent's apply (triggered by the PUT)
# runs the forward network hook -> `snapctl set` -> `meta/hooks/configure`,
# which would block on that same lock -> deadlock. So we return from configure
# FIRST, then PUT a moment later. `& disown` (NOT setsid — denied by the
# rplidar AppArmor profile, see husarion-snap-common-#rplidar-setsid) keeps the
# subshell alive past the hook's exit.
(
    sleep 2
    curl -sf --unix-socket "$SOCK" -X PUT \
        http://localhost/api/agent/v1/config/concerns/network \
        -H 'Content-Type: application/json' \
        -d "{\"values\":{${fields}}}"
) </dev/null >/dev/null 2>&1 &
disown 2>/dev/null || true
