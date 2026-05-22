#!/bin/sh
# launcher.sh — daemon launcher for the husarion-agent embedded in
# a Husarion snap. Replaces each snap's per-repo copy under
# snap/local/husarion_agent_launcher.sh.
#
# Stages shipped hooks into a writable $SNAP_COMMON/husarion-agent/
# tree the agent's hooks-runner can exec (the snap-confined $SNAP
# is read-only, and snapd refuses to introspect read-only execs on
# some revisions), then exec's the agent.
#
# Env (set by the consumer snap's snapcraft.yaml `environment:` block):
#   HA_TIER       — robot | user-pc | operator | unknown   (default: empty)
#                   Sent in the join request body; advisory only.
#                   Snaps inside a robot set "robot"; the operator
#                   laptop install sets "operator".
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
CAPS_DEFAULT="${SNAP}/usr/share/husarion-agent/capabilities.d"
CAPS_OVERRIDES="${STATE_DIR}/capabilities.d"
mkdir -p "$STATE_DIR" "$CAPS_OVERRIDES" "${SNAP_COMMON}/peer-certs"

# Stage shipped hooks into writable $SNAP_COMMON paths so the
# agent's hooks-runner can exec them. Re-copy on every (re)start
# so a snap refresh's newer hook wins. Additive copy — files an
# operator dropped under $SNAP_COMMON that aren't in shipped
# stay.
SHIPPED_HOOKS_ROOT="${SNAP}/usr/share/husarion-agent/hooks.d"
if [ -d "$SHIPPED_HOOKS_ROOT" ]; then
    for shipped_subdir in "$SHIPPED_HOOKS_ROOT"/*; do
        [ -d "$shipped_subdir" ] || continue
        cap_name=$(basename "$shipped_subdir")
        dest="${STATE_DIR}/hooks.d/${cap_name}"
        mkdir -p "$dest"
        for h in "$shipped_subdir"/*.sh; do
            [ -f "$h" ] || continue
            cp "$h" "$dest/"
            chmod 0755 "$dest/$(basename "$h")"
        done
    done
fi

export HUSARION_AGENT_HOSTNAME="${SNAP_INSTANCE_NAME:-$(basename "$0")}"

extra=""
[ -n "${HA_TIER:-}" ]      && extra="$extra --tier ${HA_TIER}"
[ -n "${HA_PEER_BIND:-}" ] && extra="$extra --peer-tls-bind ${HA_PEER_BIND}"

exec "${SNAP}/usr/bin/husarion-agent" \
    --socket "$SOCK" \
    --state-dir "$STATE_DIR" \
    --capabilities-default "$CAPS_DEFAULT" \
    --capabilities-overrides "$CAPS_OVERRIDES" \
    $extra
