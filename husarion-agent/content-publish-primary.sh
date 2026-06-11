#!/bin/sh
# content-publish-primary.sh — provider (rosbot) side. Ensure the agent-chain
# slot directory + its requests/ and certs/ subdirs exist so snapd's content
# bind-mount has a source and followers can drop CSRs into requests/. Part of
# SPEC-content-chain.md Phase 2.
#
# The husarion-agent daemon (launched with --content-join-dir) owns the actual
# advertisement — it writes ca.pem + primary.url and signs CSRs. This helper
# only GUARANTEES THE DIRECTORY EXISTS early, so it's safe to call from:
#   * the install hook (before the daemon's first boot — the dir's presence is
#     also what the shared launcher uses to select provider mode), and
#   * connect-slot-agent-chain (when the interface connects).
# Idempotent.
#
# Built-in snap env (snapd): SNAP_COMMON.
set -eu

SLOT="${SNAP_COMMON}/agent-chain"
mkdir -p "${SLOT}/requests" "${SLOT}/certs"
chmod 0755 "${SLOT}" "${SLOT}/requests" "${SLOT}/certs"
echo "content: ensured ${SLOT} (requests/, certs/)"
