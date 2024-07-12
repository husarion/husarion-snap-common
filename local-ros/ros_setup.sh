#!/bin/bash -e

source $SNAP/usr/bin/utils.sh

# Path to the ros.env file
ROS_ENV_FILE="$SNAP_COMMON/ros.env"

# Check if the ros.env file exists
if [[ ! -f "$ROS_ENV_FILE" ]]; then
    log "Copying ros.env file to $SNAP_COMMON"
    cp -r ${SNAP}/usr/share/${SNAP_NAME}/config/ros.env ${SNAP_COMMON}/
fi

# Source the ros.env file
source "$ROS_ENV_FILE"

# Execute the passed command
exec "$@"
