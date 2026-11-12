#!/bin/bash

# Copyright 2026 Husarion sp. z o.o.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Robot world: domain 0, Fast DDS, loopback + SHM only. Sourced (after utils.sh)
# by a consumer's render step; independent of the ros.* keys of
# configure_hook_ros.sh. Needs SNAP and SNAP_COMMON.

HSC_FIXED_HOST_ID_BASE=0x5b01

# Host id stock Fast DDS 2.14 computes (utils/Host.hpp compute_id): md5 over
# 12 zero bytes + the address, per non-loopback IPv4 address, folded to 16 bits.
hsc_stock_host_id() {
    local addrs
    addrs=$(ip -4 -o addr show 2>/dev/null | awk '$2 != "lo" {split($4, a, "/"); print a[1]}') || return 1
    if [ -z "$addrs" ]; then
        echo "0x17f"
        return 0
    fi

    local digest v=0 i a o
    digest=$(
        for a in $addrs; do
            IFS=. read -r -a o <<< "$a"
            head -c 12 /dev/zero
            # shellcheck disable=SC2059
            printf "$(printf '\\x%02x' "${o[@]}")"
        done | md5sum | cut -d' ' -f1
    )
    for i in 0 4 8 12 16 20 24 28; do
        v=$(( v ^ 0x${digest:$i:4} ))
    done
    printf '0x%x\n' "$v"
}

# A fixed id that differs from the stock one: a patched process then looks
# like another host to stock peers and the pair falls back to UDP loopback.
hsc_fixed_host_id() {
    local stock id
    stock=$(hsc_stock_host_id) || return 1
    id=$HSC_FIXED_HOST_ID_BASE
    while [ $(( id )) -eq $(( stock )) ]; do
        id=$(printf '0x%x' $(( id + 1 )))
    done
    echo "$id"
}

# Refuses what breaks the robot world (spec single-snap §3.1, §3.2): LOCALHOST
# discovery overrides the XML profile in rmw_fastrtps, FILTER_DIFFERENT_HOST
# drops patched <-> stock pairs. Args: env file, profile file.
hsc_validate_robot_world() {
    local env_file="$1" profile="$2"

    if grep -Eiq '^[[:space:]]*(export[[:space:]]+)?ROS_AUTOMATIC_DISCOVERY_RANGE=["'\'']?LOCALHOST' "$env_file"; then
        log_and_echo "robot world: ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST is not allowed (it replaces the Fast DDS profile with SHM + UDP on all interfaces)."
        return 1
    fi
    if grep -Eq '^[[:space:]]*(export[[:space:]]+)?ROS_LOCALHOST_ONLY=["'\'']?1' "$env_file"; then
        log_and_echo "robot world: ROS_LOCALHOST_ONLY=1 is not allowed (same as ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST)."
        return 1
    fi
    if grep -Eq 'ignoreParticipantFlags>[^<]*FILTER_DIFFERENT_HOST' "$profile"; then
        log_and_echo "robot world: ${profile} uses FILTER_DIFFERENT_HOST, which blocks patched <-> stock participants. Use NO_FILTER."
        return 1
    fi
}

# Writes robot.env + fastdds.xml into ${SNAP_COMMON}/worlds and the bare
# KEY=VALUE host env to ${SNAP_COMMON}/host-ros/ros.env. Idempotent, atomic per file.
#   --shm=true   SHM + UDP loopback, FASTDDS_SHM_MODE and a fixed FASTDDS_HOST_ID
#                for patched snap daemons (default)
#   --shm=false  UDP loopback only
# The host env carries no FASTDDS_* variables (stage 1: stock host).
render_robot_world() {
    local shm=true arg
    for arg in "$@"; do
        case "$arg" in
            --shm=true|--shm=false) shm="${arg#--shm=}" ;;
            *) log_and_echo "render_robot_world: unknown argument '${arg}'"; return 1 ;;
        esac
    done

    local templates="${HSC_WORLD_TEMPLATES:-${SNAP}/usr/share/husarion-snap-common/config/worlds}"
    local dir="${SNAP_COMMON}/worlds"
    local profile="${dir}/fastdds.xml"
    local src="${templates}/fastdds.xml"
    [ "$shm" = "false" ] && src="${templates}/udp_lo.xml"
    if [ ! -f "$src" ]; then
        log_and_echo "render_robot_world: missing template ${src}"
        return 1
    fi

    local host_id=""
    if [ "$shm" = "true" ]; then
        host_id=$(hsc_fixed_host_id) || { log_and_echo "render_robot_world: cannot compute the host id (is 'ip' available?)"; return 1; }
    fi

    mkdir -p "$dir"
    chmod 0755 "$dir"

    local tmp_xml tmp_env tmp_host
    tmp_xml=$(mktemp "${dir}/.fastdds.xml.XXXXXX")
    tmp_env=$(mktemp "${dir}/.robot.env.XXXXXX")
    tmp_host=$(mktemp "${dir}/.host.env.XXXXXX")

    cp "$src" "$tmp_xml"
    {
        echo "export ROS_DOMAIN_ID=0"
        echo "export RMW_IMPLEMENTATION=rmw_fastrtps_cpp"
        echo "export ROS_AUTOMATIC_DISCOVERY_RANGE=SYSTEM_DEFAULT"
        echo "unset ROS_LOCALHOST_ONLY ROS_NAMESPACE CYCLONEDDS_URI"
        echo "unset ZENOH_SESSION_CONFIG_URI ZENOH_ROUTER_CONFIG_URI ZENOH_ROUTER_CHECK_ATTEMPTS"
        printf 'export FASTRTPS_DEFAULT_PROFILES_FILE=%q\n' "$profile"
        if [ "$shm" = "true" ]; then
            echo "export FASTDDS_SHM_MODE=0666"
            echo "export FASTDDS_HOST_ID=${host_id}"
        else
            echo "unset FASTDDS_SHM_MODE FASTDDS_HOST_ID"
        fi
    } > "$tmp_env"
    {
        echo "ROS_DOMAIN_ID=0"
        echo "RMW_IMPLEMENTATION=rmw_fastrtps_cpp"
        echo "ROS_AUTOMATIC_DISCOVERY_RANGE=SYSTEM_DEFAULT"
        printf 'FASTRTPS_DEFAULT_PROFILES_FILE=%s\n' "$profile"
    } > "$tmp_host"

    if ! hsc_validate_robot_world "$tmp_env" "$tmp_xml"; then
        rm -f "$tmp_xml" "$tmp_env" "$tmp_host"
        return 1
    fi

    chmod 0644 "$tmp_xml" "$tmp_env" "$tmp_host"
    mkdir -p "${SNAP_COMMON}/host-ros"
    chmod 0755 "${SNAP_COMMON}/host-ros"
    mv "$tmp_xml" "$profile"
    mv "$tmp_env" "${dir}/robot.env"
    mv "$tmp_host" "${SNAP_COMMON}/host-ros/ros.env"
}
