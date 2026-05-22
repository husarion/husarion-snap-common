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

# `snapctl get peer.parent -d` returns either:
#   - the JSON subtree   `{ "parent": { "network-robot": "https://..." } }`
#   - the literal `null` when `peer.parent` is fully unset
#   - exits non-zero when `peer` itself is unset on first install
#
# We treat any of the empty-ish cases as "no overrides" and write an
# empty YAML file so the agent's next boot reliably clears stale state.
parents_subtree="$(snapctl get peer.parent -d 2>/dev/null || true)"

if [ -z "$parents_subtree" ] || [ "$parents_subtree" = "null" ]; then
    : > "$TMP_FILE"
else
    # Extract the inner map. yq's `-o yaml` flattens nested JSON to
    # the flat top-level shape peer-parents.yaml expects:
    #   network-robot: "https://cockpit.local:7443"
    #   drive: ""
    # If the subtree is `{}` (operator set + unset everything), yq emits
    # `{}\n` which the agent's loader handles fine (empty map).
    if ! echo "$parents_subtree" | "$YQ" -p json -o yaml '.parent // {}' > "$TMP_FILE"; then
        echo "configure-peer-parents.sh: yq failed to translate snap-config subtree" >&2
        rm -f "$TMP_FILE"
        exit 1
    fi
fi

mv -f "$TMP_FILE" "$PARENTS_FILE"

# The husarion-agent daemon picks up the change on its next restart.
# Trigger one so operator's `snap set peer.parent.*` takes effect
# without an explicit `snap restart`.
snapctl restart "${SNAP_INSTANCE_NAME}.husarion-agent" 2>/dev/null || true
