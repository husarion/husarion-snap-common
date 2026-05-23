#!/bin/sh
# fetch-binary.sh — download + sha256-verify the husarion-agent
# release binary into ${CRAFT_PART_BUILD}/husarion-agent.
#
# Called from the consuming snap's `husarion-agent` part's
# override-build (or override-pull). Single source-of-truth so we
# don't duplicate the ~30-line curl + sha256 dance across every
# Husarion snap. Bump HA_VERSION in the consuming snap's
# build-environment to track newer agent releases.
#
# Required env (set by the consumer's snapcraft.yaml):
#   HA_VERSION                — e.g. "0.8.0"
#   CRAFT_ARCH_BUILD_FOR      — provided by snapcraft (amd64 / arm64)
#   CRAFT_PART_BUILD          — provided by snapcraft

set -eu
: "${HA_VERSION:?fetch-binary.sh requires HA_VERSION env}"
: "${CRAFT_PART_BUILD:?must run inside a snapcraft part override-build}"
: "${CRAFT_ARCH_BUILD_FOR:?must run inside snapcraft}"

base="https://github.com/husarion/husarion-cockpit-releases/releases/download/husarion-agent/v${HA_VERSION}"
file="husarion-agent-${HA_VERSION}-linux-${CRAFT_ARCH_BUILD_FOR}"

cd "$CRAFT_PART_BUILD"
curl -fsSL -o husarion-agent       "${base}/${file}"
curl -fsSL -o husarion-agent.sha256 "${base}/${file}.sha256"

# The .sha256 from releases is `<hash>  <file-with-version-and-arch>`.
# Rename the second column to our local filename so sha256sum -c finds
# the file it's looking for.
hash=$(awk '{print $1}' husarion-agent.sha256)
printf '%s  husarion-agent\n' "$hash" > husarion-agent.sha256
sha256sum -c husarion-agent.sha256
chmod +x husarion-agent
rm -f husarion-agent.sha256
echo "fetch-binary.sh: husarion-agent v${HA_VERSION} (${CRAFT_ARCH_BUILD_FOR}) verified"
