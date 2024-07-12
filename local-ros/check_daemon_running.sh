#!/bin/bash -e

# Define a function to log and echo messages
source $SNAP/usr/bin/utils.sh

if snapctl services ${SNAP_NAME}.daemon | grep -qw active; then
    log_and_echo "to run ${SNAP_NAME} snap interactively, you need to stop the daemon first, run:"
    log_and_echo "sudo ${SNAP_NAME}.stop"
    exit 1
fi

exec $@