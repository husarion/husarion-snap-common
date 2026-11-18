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

# Robot world: domain 0, Fast DDS, UDP on 127.0.0.1 only. Sourced (after utils.sh)
# by a consumer's render step; independent of the ros.* keys of
# configure_hook_ros.sh. Needs SNAP and SNAP_COMMON.

# Refuses what breaks the robot world (spec single-snap §3.1, §3.2): LOCALHOST
# discovery overrides the XML profile in rmw_fastrtps, FILTER_DIFFERENT_HOST
# drops participants whose host id differs. Args: env file, profile file.
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
        log_and_echo "robot world: ${profile} uses FILTER_DIFFERENT_HOST, which drops participants whose host id differs. Use NO_FILTER."
        return 1
    fi
}

# Writes robot.env + fastdds.xml into ${SNAP_COMMON}/worlds and the bare
# KEY=VALUE host env to ${SNAP_COMMON}/host-ros/ros.env. Idempotent, atomic per file.
render_robot_world() {
    if [ "$#" -ne 0 ]; then
        log_and_echo "render_robot_world: takes no arguments (got '$*'); the robot world is UDP loopback only."
        return 1
    fi

    local templates="${HSC_WORLD_TEMPLATES:-${SNAP}/usr/share/husarion-snap-common/config/worlds}"
    local dir="${SNAP_COMMON}/worlds"
    local profile="${dir}/fastdds.xml"
    local src="${templates}/fastdds.xml"
    if [ ! -f "$src" ]; then
        log_and_echo "render_robot_world: missing template ${src}"
        return 1
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
        echo "unset FASTDDS_SHM_MODE FASTDDS_HOST_ID"
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

# For a sensor snap: joins the robot world another snap rendered, mounted at
# $1 (its worlds/ dir through a content plug). Writes ${SNAP_COMMON}/ros.env =
# that robot.env with the profile path rewritten to the mount (the renderer's
# /var/snap/<owner>/... path does not exist in this snap's mount namespace),
# plus HSC_ROBOT_WORLD=1 for the launcher. Returns 1 when nothing is mounted.
hsc_join_robot_world() {
    local mount="$1"
    [ -f "${mount}/robot.env" ] && [ -f "${mount}/fastdds.xml" ] || return 1

    local tmp
    tmp=$(mktemp "${SNAP_COMMON}/.ros.env.XXXXXX")
    {
        grep -v '^export FASTRTPS_DEFAULT_PROFILES_FILE=' "${mount}/robot.env"
        printf 'export FASTRTPS_DEFAULT_PROFILES_FILE=%q\n' "${mount}/fastdds.xml"
        echo "export HSC_ROBOT_WORLD=1"
    } > "$tmp"
    chmod 0644 "$tmp"
    mv "$tmp" "${SNAP_COMMON}/ros.env"
}
