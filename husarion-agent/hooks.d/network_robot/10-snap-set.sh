#!/bin/sh
# 10-snap-set.sh — generic chain follower hook for the
# `network_robot/ros_env` resource. Translates the chain payload's
# ROS_* env vars into `snapctl set ros.*=…` against the consuming
# snap's own config. The snap's configure hook then validates +
# regenerates ${SNAP_COMMON}/ros.env + restarts the snap's daemon.
#
# Ships from husarion-snap-common; consumers don't override.
#
# v2 wire vocabulary → snap-config translation:
#   HUSARION_AGENT_ROS_DOMAIN_ID                → ros.domain-id
#   HUSARION_AGENT_ROS_NAMESPACE                → ros.namespace
#   HUSARION_AGENT_RMW_IMPLEMENTATION + URI     → ros.transport (token)
#   HUSARION_AGENT_ROS_LOCALHOST_ONLY (bool)    → ros.localhost-only (1/"")
#   HUSARION_AGENT_ROS_AUTOMATIC_DISCOVERY_RANGE→ ros.automatic-discovery-range
#   HUSARION_AGENT_ROS_STATIC_PEERS             → ros.static-peers
#
# ros.transport encodes BOTH the RMW family AND the profile file:
#   <kind>/<name>  → $SNAP_COMMON/rmw/<kind>/<name>.<ext>
#   rmw_<X>_cpp    → library defaults, no profile
# See the configure_hook_ros.sh §"Token grammar" comment for the
# full spec.
set -eu

LOCKFILE="${SNAP_COMMON}/husarion-agent/.snap-apply-in-flight"
mkdir -p "${SNAP_COMMON}/husarion-agent"
touch "$LOCKFILE"
trap 'setsid sh -c "sleep 60 && rm -f \"$LOCKFILE\"" </dev/null >/dev/null 2>&1 &' EXIT

# Boolean ROS_LOCALHOST_ONLY → snap's "1" / "" form.
case "${HUSARION_AGENT_ROS_LOCALHOST_ONLY:-false}" in
    1|true) localhost_only_snap=1 ;;
    *)      localhost_only_snap="" ;;
esac

# ROS_AUTOMATIC_DISCOVERY_RANGE → lowercase snap form. Empty maps
# to `subnet` (ROS 2 default per Improved-Dynamic-Discovery docs).
case "${HUSARION_AGENT_ROS_AUTOMATIC_DISCOVERY_RANGE:-}" in
    "OFF")              range=off ;;
    "LOCALHOST")        range=localhost ;;
    "SUBNET" | "")      range=subnet ;;
    "SYSTEM_DEFAULT")   range=system_default ;;
    *)                  range=subnet ;;
esac

# RMW_IMPLEMENTATION + corresponding URI → snap's ros.transport token.
case "${HUSARION_AGENT_RMW_IMPLEMENTATION:-rmw_fastrtps_cpp}" in
    rmw_fastrtps_cpp)
        uri="${HUSARION_AGENT_FASTRTPS_DEFAULT_PROFILES_FILE:-}"
        if [ -n "$uri" ]; then
            transport="fastdds/$(basename "$uri" .xml)"
        else
            transport="rmw_fastrtps_cpp"
        fi
        ;;
    rmw_cyclonedds_cpp)
        uri="${HUSARION_AGENT_CYCLONEDDS_URI:-}"
        if [ -n "$uri" ]; then
            transport="cyclonedds/$(basename "$uri" .xml)"
        else
            transport="rmw_cyclonedds_cpp"
        fi
        ;;
    rmw_zenoh_cpp)
        uri="${HUSARION_AGENT_ZENOH_SESSION_CONFIG_URI:-}"
        if [ -n "$uri" ]; then
            transport="zenoh/$(basename "$uri" .json5)"
        else
            transport="rmw_zenoh_cpp"
        fi
        ;;
    *)
        transport="rmw_fastrtps_cpp"
        ;;
esac

snapctl set \
    "ros.domain-id=${HUSARION_AGENT_ROS_DOMAIN_ID:-0}" \
    "ros.namespace=${HUSARION_AGENT_ROS_NAMESPACE:-}" \
    "ros.transport=${transport}" \
    "ros.localhost-only=${localhost_only_snap}" \
    "ros.automatic-discovery-range=${range}" \
    "ros.static-peers=${HUSARION_AGENT_ROS_STATIC_PEERS:-}"

# `snapctl set` from a daemon-child doesn't fire the snap's
# configure hook automatically — call it explicitly so ros.env
# regenerates + the snap's main daemon picks up the new config.
"${SNAP}/meta/hooks/configure"
