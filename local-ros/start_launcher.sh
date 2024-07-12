#!/bin/bash -e

source $SNAP/usr/bin/utils.sh

log "Start ${SNAP_NAME}.daemon service"
snapctl start --enable ${SNAP_NAME}.daemon 2>&1 || true

