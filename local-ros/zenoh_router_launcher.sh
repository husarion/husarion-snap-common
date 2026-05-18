#!/bin/bash
#
# Launcher for rmw_zenohd. Started as a daemon by the rosbot snap;
# always running but only useful when the operator selects a zenoh
# transport via `ros.transport=rmw_zenoh_cpp` or `ros.transport=zenoh/<name>`
# (gated behind HSC_ALLOW_ZENOH=1; see configure_hook_ros.sh).
#
# This script runs AFTER the snap's command-chain (ros_setup.sh) has
# already sourced the ROS overlay AND the configure-hook-generated
# ${SNAP_COMMON}/ros.env. So RMW_IMPLEMENTATION, ZENOH_ROUTER_CONFIG_URI
# etc. are already in our environment — do NOT re-source anything here.
# Doubling up corrupts bash's function table (pop_var_context errors).
#
# When the operator is on a non-zenoh transport the env var is unset and
# the router falls back to its built-in defaults — harmless because no
# client will connect anyway.

set -e

# shellcheck source=/dev/null
source "$SNAP/usr/bin/utils.sh"

log_and_echo "Starting rmw_zenohd${ZENOH_ROUTER_CONFIG_URI:+ with config $ZENOH_ROUTER_CONFIG_URI}"
exec ros2 run rmw_zenoh_cpp rmw_zenohd
