#!/bin/sh
# configure-peer-parents.sh — snap configure-hook helper.
#
# Reads the operator's `peer.parent.<cap>=URL` snap-config keys and
# materialises them as $SNAP_COMMON/husarion-agent/peer-parents.yaml
# for the snap-internal husarion-agent to consume on its next restart.
#
# The agent reads this file on boot (see husarion-agent/src/peer_parents.rs)
# and uses it to override the `follows:` block of any capability whose
# name matches a top-level YAML key. Empty value = clear `follows:`
# (standalone master); non-empty URL = follow that primary.
#
# Operator surface:
#
#   # Make the cockpit the parent for network_robot:
#   sudo snap set rosbot peer.parent.network-robot=https://cockpit.local:7443
#
#   # Standalone master for drive (robot owns its kinematics):
#   sudo snap unset rosbot peer.parent.drive
#
#   # Inspect:
#   sudo snap get rosbot peer
#
# Cap-name canonicalisation (kebab → snake; e.g. `network-robot` →
# `network_robot`) happens agent-side in peer_parents::apply. This
# script just emits the operator's literal keys.
#
# Invocation from the consumer snap's `snap/hooks/configure`:
#
#   if [ -x "$SNAP/usr/share/husarion-snap-common/husarion-agent/configure-peer-parents.sh" ]; then
#       sh "$SNAP/usr/share/husarion-snap-common/husarion-agent/configure-peer-parents.sh"
#   fi

set -eu

# `snap configure` hooks run with $SNAP + $SNAP_COMMON set by snapd.
# Guard against being run outside that context so a developer who
# sources this file by accident doesn't litter the host.
: "${SNAP_COMMON:?must be set (sourced from a snap configure hook)}"
: "${SNAP:?must be set (sourced from a snap configure hook)}"

PARENTS_FILE="${SNAP_COMMON}/husarion-agent/peer-parents.yaml"
TMP_FILE="${PARENTS_FILE}.tmp.$$"
YQ="${SNAP}/usr/bin/yq"

mkdir -p "$(dirname "$PARENTS_FILE")"

# `snapctl get peer.parent` (no -d) returns the value of the dotted
# key directly. For a map-typed subtree it emits the inner JSON object
# as-is, which yq converts to top-level YAML keys without further
# unwrapping. Example outputs on snapd 2.75:
#
#   $ snapctl get peer.parent
#   {
#       "network-robot": "https://cockpit.local:7443"
#   }
#
#   $ snapctl get peer.parent      # nothing set
#                                  # (empty output, exit 0)
#
# We intentionally avoid `-d`. `snapctl get peer.parent -d` wraps the
# subtree under the literal key `"peer.parent"`, which yq can't extract
# without escaping (`."peer.parent"` is brittle across yq versions).
parents_subtree="$(snapctl get peer.parent 2>/dev/null || true)"

if [ -z "$parents_subtree" ] || [ "$parents_subtree" = "null" ]; then
    : > "$TMP_FILE"
else
    # Convert JSON object → flat YAML keys. peer-parents.yaml shape is:
    #   network-robot: "https://cockpit.local:7443"
    #   drive: ""
    # If the subtree is `{}` (everything unset), yq emits `{}\n` which
    # the agent's loader handles fine (empty map → no overrides).
    if ! echo "$parents_subtree" | "$YQ" -p json -o yaml '. // {}' > "$TMP_FILE"; then
        echo "configure-peer-parents.sh: yq failed to translate snap-config subtree" >&2
        rm -f "$TMP_FILE"
        exit 1
    fi
fi

# Only swap the file in + restart the daemon if the content actually
# changed. The configure hook fires on EVERY `snap set`, including
# `ros.*` / `driver.*` keys unrelated to peer.parent. Restarting the
# daemon on every such change would race with in-flight apply hooks
# (leaving their lockfile stuck for 60s) and lose broadcasts to
# followers. snap_watch sits in the agent process, so killing it
# mid-event silently drops downstream propagation.
old_hash=""
new_hash=$(sha256sum < "$TMP_FILE" | awk '{print $1}')
if [ -f "$PARENTS_FILE" ]; then
    old_hash=$(sha256sum < "$PARENTS_FILE" | awk '{print $1}')
fi

if [ "$old_hash" = "$new_hash" ]; then
    rm -f "$TMP_FILE"
    exit 0
fi

mv -f "$TMP_FILE" "$PARENTS_FILE"

# Content actually changed — trigger a restart so the agent re-reads
# peer-parents.yaml. The husarion-agent daemon reads the file on boot
# (see husarion-agent/src/peer_parents.rs); there's no hot-reload yet.
snapctl restart "${SNAP_INSTANCE_NAME}.husarion-agent" 2>/dev/null || true
