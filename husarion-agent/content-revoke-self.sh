#!/bin/sh
# content-revoke-self.sh — follower side. On content-interface disconnect (the
# disconnect-plug-agent-chain hook), drop a revoke marker into the still-mounted
# shared dir so the provider (rosbot) auto-revokes THIS follower's content cert.
# Part of SPEC-content-chain.md (revoke-marker drop-box, symmetric with the CSR
# flow).
#
# The follower knows its own CN (SNAP_INSTANCE_NAME) and, because snapd runs
# disconnect hooks BEFORE tearing the connection down, the bind-mount is still
# live here. Best-effort + idempotent: if the mount is already gone (e.g. an
# abrupt removal), there's nothing we can do from here — rosbot's stale-cert
# entry is harmless on a same-host trust domain and re-signs on reconnect.
#
# Built-in snap env (snapd): SNAP_COMMON, SNAP_INSTANCE_NAME.
set -eu

UP="${SNAP_COMMON}/agent-chain-upstream"
if [ ! -d "$UP" ]; then
    echo "content-revoke: ${UP} already gone — nothing to do"
    exit 0
fi
mkdir -p "${UP}/revoke"
: > "${UP}/revoke/${SNAP_INSTANCE_NAME}"
echo "content-revoke: dropped revoke marker for ${SNAP_INSTANCE_NAME}"
