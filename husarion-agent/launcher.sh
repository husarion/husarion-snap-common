#!/bin/sh
# launcher.sh — daemon launcher for the husarion-agent embedded in
# a Husarion snap. Replaces each snap's per-repo copy under
# snap/local/husarion_agent_launcher.sh.
#
# Seeds the files-first config-root (agent.yaml / follow.yaml / config/ /
# hooks/ / manifests/) into the writable $SNAP_COMMON tree the agent reads
# and execs from (the snap-confined $SNAP is read-only, and snapd refuses
# to introspect read-only execs on some revisions), then exec's the agent.
#
# Env (set by the consumer snap's snapcraft.yaml `environment:` block):
#   HA_PEER_BIND  — `0.0.0.0:<port>` to start an in-snap mTLS
#                   listener (cascading-primary mode). Only the
#                   rosbot snap currently sets this (:7444). Leaf
#                   followers omit it.
#
# Built-in snap env (always set by snapd inside the daemon child):
#   SNAP_INSTANCE_NAME, SNAP_COMMON, SNAP
set -eu

STATE_DIR="${SNAP_COMMON}/husarion-agent"
SOCK="${STATE_DIR}/agent.sock"
PANELS_DEFAULT="${SNAP}/usr/share/husarion-agent/panels.d"
PANELS_OVERRIDES="${STATE_DIR}/panels.d"
mkdir -p "$STATE_DIR" "$PANELS_OVERRIDES" "${SNAP_COMMON}/peer-certs"

# Seed the files-first config-root from the snap-shipped seed.
#   identity + topology + initial config (agent.yaml / follow.yaml /
#   config/) are seeded ONLY IF ABSENT, so operator edits and config
#   pulled from an upstream survive a snap refresh.
#   hooks/ + manifests/ are re-copied on every (re)start so a refresh's
#   newer code wins (shipped > whatever was staged before).
SEED_ROOT="${SNAP}/usr/share/husarion-agent/config-seed"
if [ -d "$SEED_ROOT" ]; then
    for item in agent.yaml follow.yaml config; do
        if [ -e "$SEED_ROOT/$item" ] && [ ! -e "$STATE_DIR/$item" ]; then
            cp -a "$SEED_ROOT/$item" "$STATE_DIR/$item"
        fi
    done
    if [ -d "$SEED_ROOT/hooks" ]; then
        mkdir -p "$STATE_DIR/hooks"
        cp -a "$SEED_ROOT/hooks/." "$STATE_DIR/hooks/"
        find "$STATE_DIR/hooks" -type f -exec chmod 0755 {} +
    fi
    if [ -d "$SEED_ROOT/manifests" ]; then
        mkdir -p "$STATE_DIR/manifests"
        cp -a "$SEED_ROOT/manifests/." "$STATE_DIR/manifests/"
    fi
fi

export HUSARION_AGENT_HOSTNAME="${SNAP_INSTANCE_NAME:-$(basename "$0")}"

extra=""
[ -n "${HA_PEER_BIND:-}" ] && extra="$extra --peer-tls-bind ${HA_PEER_BIND}"

exec "${SNAP}/usr/bin/husarion-agent" \
    --socket "$SOCK" \
    --state-dir "$STATE_DIR" \
    --config-root "$STATE_DIR" \
    --panels-default "$PANELS_DEFAULT" \
    --panels-overrides "$PANELS_OVERRIDES" \
    $extra
