#!/bin/sh
# content-join-follower.sh — idempotent same-host content-interface join for a
# follower snap (rplidar / depthai). Drops a CSR into the mounted agent-chain
# upstream dir and waits for the provider (rosbot) to sign it. NO bootstrap
# token: authorization IS the snap content connection (snapd only auto-connects
# same-publisher snaps). Part of SPEC-content-chain.md Phase 2.
#
# Idempotent — exits 0 without acting when:
#   * the provider hasn't advertised yet (no primary.url) — interface not
#     connected on its side, or its daemon not up;
#   * a cert bundle for the provider already exists (already joined).
# Safe to call from BOTH connect-plug-agent-chain (restart on success) and the
# launcher at boot (`no-restart`, backgrounded).
#
# Arg:
#   no-restart  → pass --no-restart to content-join (the agent is (re)starting
#                 anyway). Default: content-join `snapctl restart`s the agent so
#                 its fspeer follow tasks pick up the fresh certs immediately.
#
# Built-in snap env (snapd): SNAP, SNAP_COMMON, SNAP_INSTANCE_NAME.
set -eu

UP="${SNAP_COMMON}/agent-chain-upstream"
CERTS="${SNAP_COMMON}/peer-certs"
FOLLOW_OUT="${SNAP_COMMON}/husarion-agent/follow.yaml"

if [ ! -f "${UP}/primary.url" ]; then
    echo "content-join: no ${UP}/primary.url yet (provider not connected) — skipping"
    exit 0
fi

# Already joined? primary.url line 1 is the provider URL; the bundle is keyed on
# its host (<host>.pem under peer-certs).
HOST=$(sed -n '1p' "${UP}/primary.url" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://([^:/]+).*#\1#')
if [ -n "${HOST}" ] && [ -f "${CERTS}/${HOST}.pem" ]; then
    echo "content-join: cert for ${HOST} already present — nothing to do"
    exit 0
fi

restart_arg=""
[ "${1:-}" = "no-restart" ] && restart_arg="--no-restart"

# shellcheck disable=SC2086  # restart_arg is an intentional optional flag
exec "${SNAP}/usr/bin/husarion-agent" content-join \
    --dir "${UP}" \
    --cn "${SNAP_INSTANCE_NAME}" \
    --cert-dir "${CERTS}" \
    --follow-out "${FOLLOW_OUT}" \
    ${restart_arg}
