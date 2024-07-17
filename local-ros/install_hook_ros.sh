#!/bin/bash -e

# Define a function to log messages
source $SNAP/usr/bin/utils.sh

source_ros

if [[ $ROS_DISTRO == "humble" ]]; then
  snapctl set ros.localhost-only=0
elif [[ $ROS_DISTRO == "jazzy" ]]; then
  snapctl set ros.automatic-discovery-range="subnet"
  snapctl set ros.static-peers="" # unset
fi

snapctl set ros.transport="udp"
snapctl set ros.domain-id=0
snapctl set ros.namespace="" # unset

# copy DDS config files to shared folder
cp -r $SNAP/usr/share/husarion-snap-common/config/*.xml ${SNAP_COMMON}/