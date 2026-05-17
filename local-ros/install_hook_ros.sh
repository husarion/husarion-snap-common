#!/bin/bash -e
#
# Initial ROS-side setup on snap install. Runs from the snap's
# `install` hook (e.g. rosbot-snap's snap/hooks/install).
#
# Seeds default `ros.*` config keys + populates the
# ${SNAP_COMMON}/rmw/ tree from the factory snapshot baked into
# $SNAP/usr/share/husarion-snap-common/config/rmw/. Also leaves
# back-compat symlinks at the legacy flat paths
# `${SNAP_COMMON}/dds-config-*.xml` so external callers that read
# the old paths directly keep working through the refactor.

# Define a function to log messages
source $SNAP/usr/bin/utils.sh

source_ros

if [[ $ROS_DISTRO == "humble" ]]; then
  snapctl set ros.localhost-only=''
elif [[ $ROS_DISTRO == "jazzy" ]]; then
  snapctl set ros.automatic-discovery-range="" # unset
  snapctl set ros.static-peers='' # unset
fi

snapctl set ros.transport="udp"
snapctl set ros.domain-id=0
snapctl set ros.namespace="" # unset

# ---------------------------------------------------------------- rmw/ tree
#
# Layout (since 0.6.0):
#
#   ${SNAP_COMMON}/rmw/
#       fastdds/{udp,shm,udp-lo}.xml
#       cyclonedds/udp-lo.xml
#       zenoh/{default,shm}.json5
#       zenoh-router/{default,shm}-router.json5
#
# The configure-hook reads from this layout. Tokens passed to
# `ros.transport=…` resolve to file paths under here (see
# configure_hook_ros.sh's case statement).
SRC="${SNAP}/usr/share/husarion-snap-common/config/rmw"
DST="${SNAP_COMMON}/rmw"
mkdir -p "${DST}/fastdds" "${DST}/cyclonedds" "${DST}/zenoh" "${DST}/zenoh-router"

# Copy the factory snapshot in. The install hook should always
# have the factory-default state on first install, so we overwrite.
# Operator edits between installs survive `snap refresh` (the
# post-refresh hook doesn't touch these files); only a `snap remove`
# + `snap install` cycle resets them.
for sub in fastdds cyclonedds zenoh zenoh-router; do
    if [ -d "${SRC}/${sub}" ]; then
        cp -rf "${SRC}/${sub}/." "${DST}/${sub}/"
    fi
done

# ---------------------------------------------------------------- back-compat
#
# Legacy flat paths (pre-0.6.0): callers that read
# `${SNAP_COMMON}/dds-config-<token>.xml` directly keep working
# via symlinks into the new rmw/ tree. The snap's own
# configure_hook_ros.sh DOESN'T read these — they exist only for
# external callers (the husarion-cockpit agent's network
# capability auto-discovers them via enum_from_glob, third-party
# scripts, ros2 invocations from the host bash sourcing the old
# ros.env, etc.).
ln -sfn rmw/fastdds/udp.xml       "${SNAP_COMMON}/dds-config-udp.xml"
ln -sfn rmw/fastdds/shm.xml       "${SNAP_COMMON}/dds-config-shm.xml"
ln -sfn rmw/fastdds/udp-lo.xml    "${SNAP_COMMON}/dds-config-udp-lo.xml"
ln -sfn rmw/cyclonedds/udp-lo.xml "${SNAP_COMMON}/dds-config-udp-lo-cyclone.xml"
