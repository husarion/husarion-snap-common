#!/bin/bash -e

source $SNAP/usr/bin/utils.sh

log "Restart ${SNAP_NAME}.daemon service"
snapctl restart ${SNAP_NAME}.daemon 2>&1 || true
