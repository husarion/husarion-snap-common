#!/bin/bash -e

# Define a function to log messages
source $SNAP/usr/bin/utils.sh

snapctl set ros.transport="udp"
snapctl set ros.localhost-only=0
snapctl set ros.domain-id=0
snapctl set ros.namespace! # unset

if ! snapctl is-connected ros-humble-ros-base; then
  log "Plug 'ros-humble-ros-base' isn't connected, please run:"
  log "sudo snap connect ${SNAP_NAME}:ros-humble-ros-base ros-humble-ros-base:ros-humble-ros-base"
fi

if ! snapctl is-connected shm-plug; then
  log "Plug 'shm-plug' isn't connected, please run:"
  log "sudo snap connect ${SNAP_NAME}:shm-plug ${SNAP_NAME}:shm-slot"
fi

# copy DDS config files to shared folder
cp -r $SNAP/usr/share/husarion-snap-common/config/*.xml ${SNAP_COMMON}/