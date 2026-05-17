#!/bin/bash -e

# The configure hook is called every time one the following actions happen:
# - initial snap installation
# - snap refresh
# - whenever the user runs snap set|unset to change a configuration option

# Define a function to log and echo messages
source $SNAP/usr/bin/utils.sh

source_ros

# Create the ${SNAP_COMMON}/ros.env file and export variables (for bash session running ROS2)
ROS_ENV_FILE="${SNAP_COMMON}/ros.env"

# Create the ${SNAP_COMMON}/ros.env file and export variables (for bash session running ROS2)
ROS_SNAP_ARGS="${SNAP_COMMON}/ros_snap_args"

rm -rf "${ROS_ENV_FILE}.tmp"
rm -rf "${ROS_SNAP_ARGS}.tmp"

if [[ $ROS_DISTRO == "humble" ]]; then
  VALID_ROS_KEYS=("localhost-only" "domain-id" "transport" "namespace")

  # Call the validation function
  validate_keys "ros" VALID_ROS_KEYS[@]
elif [[ $ROS_DISTRO == "jazzy" ]]; then
  VALID_ROS_KEYS=("localhost-only" "domain-id" "transport" "namespace" "automatic-discovery-range" "static-peers")

  # Call the validation function
  validate_keys "ros" VALID_ROS_KEYS[@]

  # validate the ROS_AUTOMATIC_DISCOVERY_RANGE
  ROS_AUTOMATIC_DISCOVERY_RANGE="$(snapctl get ros.automatic-discovery-range)"

  VALID_ROS_AUTOMATIC_DISCOVERY_RANGE_OPTIONS=("subnet" "localhost" "off" "system_default")
  validate_option --allow-unset "ros.automatic-discovery-range" VALID_ROS_AUTOMATIC_DISCOVERY_RANGE_OPTIONS[@]

  ROS_AUTOMATIC_DISCOVERY_RANGE="$(snapctl get ros.automatic-discovery-range)"

  if [ -n "$ROS_AUTOMATIC_DISCOVERY_RANGE" ]; then
    echo "export ROS_AUTOMATIC_DISCOVERY_RANGE=$(echo "$ROS_AUTOMATIC_DISCOVERY_RANGE" | tr '[:lower:]' '[:upper:]')" >> "${ROS_ENV_FILE}.tmp"
    echo "ros.automatic-discovery-range=${ROS_AUTOMATIC_DISCOVERY_RANGE}" >> ${ROS_SNAP_ARGS}.tmp
  else
    echo "unset ROS_AUTOMATIC_DISCOVERY_RANGE" >> "${ROS_ENV_FILE}.tmp"
    echo "ros.automatic-discovery-range=''" >> ${ROS_SNAP_ARGS}.tmp
    snapctl set ros.automatic-discovery-range=''
  fi
  
  # validate the ROS_STATIC_PEERS
  validate_peers_list --allow-unset "ros.static-peers"

  ROS_STATIC_PEERS="$(snapctl get ros.static-peers)"

  if [ -n "$ROS_STATIC_PEERS" ]; then
    echo "export ROS_STATIC_PEERS='${ROS_STATIC_PEERS}'" >> "${ROS_ENV_FILE}.tmp"
    echo "ros.static-peers='${ROS_STATIC_PEERS}'" >> ${ROS_SNAP_ARGS}.tmp
  else
    echo "unset ROS_STATIC_PEERS" >> "${ROS_ENV_FILE}.tmp"
    echo "ros.static-peers=''" >> ${ROS_SNAP_ARGS}.tmp
    snapctl set ros.static-peers=''
  fi

else
  log_and_echo "ROS 2 \"$ROS_DISTRO\" is not supported by this snap."
fi

# Make sure ROS_LOCALHOST_ONLY is valid
VALID_ROS_LOCALHOST_ONLY_OPTIONS=(1 0)
validate_option --allow-unset "ros.localhost-only" VALID_ROS_LOCALHOST_ONLY_OPTIONS[@]

ROS_LOCALHOST_ONLY="$(snapctl get ros.localhost-only)"

if [ -n "$ROS_LOCALHOST_ONLY" ]; then
  echo "export ROS_LOCALHOST_ONLY=${ROS_LOCALHOST_ONLY}" >> "${ROS_ENV_FILE}.tmp"
  echo "ros.localhost-only=${ROS_LOCALHOST_ONLY}" >> ${ROS_SNAP_ARGS}.tmp
else
  echo "unset ROS_LOCALHOST_ONLY" >> "${ROS_ENV_FILE}.tmp"
  echo "ros.localhost-only=''" >> ${ROS_SNAP_ARGS}.tmp
  snapctl set ros.localhost-only=''
fi

# Make sure ROS_DOMAIN_ID is valid
SUPPORTED_RANGE=(0 232)
validate_number "ros.domain-id" SUPPORTED_RANGE[@]

ROS_DOMAIN_ID="$(snapctl get ros.domain-id)"

echo "export ROS_DOMAIN_ID=${ROS_DOMAIN_ID}" >> "${ROS_ENV_FILE}.tmp"
echo "ros.domain-id=${ROS_DOMAIN_ID}" >> ${ROS_SNAP_ARGS}.tmp

# Validate the ROS_NAMESPACE

validate_regex --allow-unset "ros.namespace" "^[0-9a-z_-]{1,20}$"

ROS_NAMESPACE=$(snapctl get ros.namespace)

if [ -n "$ROS_NAMESPACE" ]; then
  echo "export ROS_NAMESPACE=${ROS_NAMESPACE}" >> "${ROS_ENV_FILE}.tmp"
  echo "ros.namespace=${ROS_NAMESPACE}" >> ${ROS_SNAP_ARGS}.tmp
else
  echo "unset ROS_NAMESPACE" >> "${ROS_ENV_FILE}.tmp"
  echo "ros.namespace=''" >> ${ROS_SNAP_ARGS}.tmp
  snapctl set ros.namespace=''
fi

TRANSPORT_SETTING="$(snapctl get ros.transport)"

# -----------------------------------------------------------------
# Token grammar — `ros.transport=<token>` accepts:
#
#   LEGACY (back-compat aliases — map to new layout):
#     udp             → fastdds/udp.xml
#     shm             → fastdds/shm.xml
#     udp-lo          → fastdds/udp-lo.xml
#     udp-lo-cyclone  → cyclonedds/udp-lo.xml
#     rmw_fastrtps_cpp  → FastDDS, no profile XML (library default)
#     rmw_cyclonedds_cpp → CycloneDDS, no profile XML
#
#   CANONICAL (since 0.6.0):
#     fastdds/<X>     → ${SNAP_COMMON}/rmw/fastdds/<X>.xml
#     cyclonedds/<X>  → ${SNAP_COMMON}/rmw/cyclonedds/<X>.xml
#
#   FALLBACK (back-compat for operator-uploaded files):
#     <X>             → if ${SNAP_COMMON}/dds-config-<X>.xml exists
#                       (legacy flat path; check_xml_profile_type
#                       dispatches FastDDS vs Cyclone by content)
#
# Resolved into three variables consumed below:
#   RMW_IMPL  — rmw_fastrtps_cpp / rmw_cyclonedds_cpp
#   PROFILE   — absolute filesystem path, or empty for "use library
#               default"
#   PROFILE_KIND — fastdds / cyclonedds (for env-var routing)
#
# Zenoh (`rmw_zenoh_cpp`, `zenoh`, `zenoh/<X>`) is REJECTED — see the
# block below the case statement. The factory configs under
# ${SNAP_COMMON}/rmw/zenoh{,-router}/ are kept as dormant data; the
# block can be flipped back on with a one-line revert once
# micro_ros_agent ships with dynamic RMW loading (currently statically
# linked to FastDDS, so its motor-feedback topics never reach
# rmw_zenoh_cpp subscribers).

RMW_IMPL=""
PROFILE=""
PROFILE_KIND=""

list_available() {
    log_and_echo "Available tokens:"
    log_and_echo "  rmw_fastrtps_cpp, rmw_cyclonedds_cpp"
    for sub in fastdds cyclonedds; do
        local dir="${SNAP_COMMON}/rmw/${sub}"
        [ -d "$dir" ] || continue
        for f in "$dir"/*.xml; do
            [ -f "$f" ] || continue
            local name; name=$(basename "$f" ".xml")
            log_and_echo "  ${sub}/${name}"
        done
    done
    log_and_echo "Legacy aliases (still accepted): udp, shm, udp-lo, udp-lo-cyclone"
}

# Zenoh is currently blocked at the validator level. Re-enable by
# moving these patterns back into the case statement below and
# restoring the `zenoh)` env-emission arm further down.
case "$TRANSPORT_SETTING" in
    rmw_zenoh_cpp|zenoh|zenoh/*)
        log_and_echo "'${TRANSPORT_SETTING}' (zenoh) is not currently supported by the rosbot snap."
        log_and_echo "Reason: micro_ros_agent is statically linked to FastDDS and cannot publish"
        log_and_echo "  motor-feedback topics into the rmw_zenoh_cpp graph. Activation of the"
        log_and_echo "  ros2_control hardware interface times out and the driver enters a death loop."
        log_and_echo "Workaround: use a FastDDS transport (udp / shm / udp-lo / fastdds/<X>) or Cyclone."
        list_available
        exit 1
        ;;
esac

case "$TRANSPORT_SETTING" in
    # --- RMW-only tokens (no profile file) ---
    rmw_fastrtps_cpp)
        RMW_IMPL="rmw_fastrtps_cpp"
        PROFILE_KIND="fastdds"
        ;;
    rmw_cyclonedds_cpp)
        RMW_IMPL="rmw_cyclonedds_cpp"
        PROFILE_KIND="cyclonedds"
        ;;
    # --- New canonical: <kind>/<name> ---
    fastdds/*)
        RMW_IMPL="rmw_fastrtps_cpp"
        PROFILE_KIND="fastdds"
        PROFILE="${SNAP_COMMON}/rmw/fastdds/${TRANSPORT_SETTING#fastdds/}.xml"
        ;;
    cyclonedds/*)
        RMW_IMPL="rmw_cyclonedds_cpp"
        PROFILE_KIND="cyclonedds"
        PROFILE="${SNAP_COMMON}/rmw/cyclonedds/${TRANSPORT_SETTING#cyclonedds/}.xml"
        ;;
    # --- Legacy short tokens (FastDDS) ---
    udp)
        RMW_IMPL="rmw_fastrtps_cpp"
        PROFILE_KIND="fastdds"
        PROFILE="${SNAP_COMMON}/rmw/fastdds/udp.xml"
        ;;
    shm)
        RMW_IMPL="rmw_fastrtps_cpp"
        PROFILE_KIND="fastdds"
        PROFILE="${SNAP_COMMON}/rmw/fastdds/shm.xml"
        ;;
    udp-lo)
        RMW_IMPL="rmw_fastrtps_cpp"
        PROFILE_KIND="fastdds"
        PROFILE="${SNAP_COMMON}/rmw/fastdds/udp-lo.xml"
        ;;
    # --- Legacy short token (Cyclone) ---
    udp-lo-cyclone)
        RMW_IMPL="rmw_cyclonedds_cpp"
        PROFILE_KIND="cyclonedds"
        PROFILE="${SNAP_COMMON}/rmw/cyclonedds/udp-lo.xml"
        ;;
    # --- Fallback: operator-uploaded files at the legacy flat
    #     path (dds-config-<X>.xml). Auto-detect FastDDS vs Cyclone
    #     by XML content. Kept so the rosbot snap doesn't break
    #     installations that pre-date the rmw/ refactor.
    *)
        legacy_path="${SNAP_COMMON}/dds-config-${TRANSPORT_SETTING}.xml"
        if [ -f "$legacy_path" ] || [ -L "$legacy_path" ]; then
            profile_type=$(check_xml_profile_type "$legacy_path")
            case "$profile_type" in
                rmw_fastrtps_cpp)
                    RMW_IMPL="rmw_fastrtps_cpp"
                    PROFILE_KIND="fastdds"
                    PROFILE="$legacy_path"
                    ;;
                rmw_cyclonedds_cpp)
                    RMW_IMPL="rmw_cyclonedds_cpp"
                    PROFILE_KIND="cyclonedds"
                    PROFILE="$legacy_path"
                    ;;
                *)
                    log_and_echo "'${TRANSPORT_SETTING}' resolves to $legacy_path but the XML profile type couldn't be detected."
                    exit 1
                    ;;
            esac
        else
            log_and_echo "'${TRANSPORT_SETTING}' is not a valid value for 'ros.transport'."
            list_available
            exit 1
        fi
        ;;
esac

# Profile file existence check (skip when there's no profile, i.e.
# the rmw_<X>_cpp / zenoh "use library defaults" tokens).
if [ -n "$PROFILE" ] && [ ! -e "$PROFILE" ]; then
    log_and_echo "'${TRANSPORT_SETTING}' resolves to '${PROFILE}' which doesn't exist."
    list_available
    exit 1
fi

# SHM plug check — FastDDS SHM transport (also kicks in for the
# 'shm' legacy alias). Other FastDDS profiles use UDP; the SHM
# plug isn't required.
if [ "$TRANSPORT_SETTING" = "rmw_fastrtps_cpp" ] || [ "$TRANSPORT_SETTING" = "shm" ] || [ "$TRANSPORT_SETTING" = "fastdds/shm" ]; then
  if ! snapctl is-connected shm-plug; then
    log_and_echo "to use 'rmw_fastrtps_cpp' and 'shm' transport shm-plug need to be connected, please run:"
    log_and_echo "sudo snap connect ${SNAP_NAME}:shm-plug ${SNAP_NAME}:shm-slot"
    exit 1
  fi
fi

# ---- Emit the env vars --------------------------------------------------
#
# Always unset the env vars OTHER than the one we're about to set,
# so the daemon doesn't see stale config from a previous transport.
echo "export RMW_IMPLEMENTATION=${RMW_IMPL}" >> "${ROS_ENV_FILE}.tmp"
case "$PROFILE_KIND" in
    fastdds)
        echo "unset CYCLONEDDS_URI" >> "${ROS_ENV_FILE}.tmp"
        if [ -n "$PROFILE" ]; then
            echo "export FASTRTPS_DEFAULT_PROFILES_FILE=${PROFILE}" >> "${ROS_ENV_FILE}.tmp"
        else
            echo "unset FASTRTPS_DEFAULT_PROFILES_FILE" >> "${ROS_ENV_FILE}.tmp"
        fi
        ;;
    cyclonedds)
        echo "unset FASTRTPS_DEFAULT_PROFILES_FILE" >> "${ROS_ENV_FILE}.tmp"
        if [ -n "$PROFILE" ]; then
            echo "export CYCLONEDDS_URI=file://${PROFILE}" >> "${ROS_ENV_FILE}.tmp"
        else
            echo "unset CYCLONEDDS_URI" >> "${ROS_ENV_FILE}.tmp"
        fi
        ;;
esac

# Always unset the zenoh env vars so a previous zenoh transport (now
# rejected by the validator above) doesn't leave stale env behind.
echo "unset ZENOH_SESSION_CONFIG_URI" >> "${ROS_ENV_FILE}.tmp"
echo "unset ZENOH_ROUTER_CHECK_ATTEMPTS" >> "${ROS_ENV_FILE}.tmp"

echo "ros.transport=${TRANSPORT_SETTING}" >> ${ROS_SNAP_ARGS}.tmp


# Make sure ros-humble-ros-base is connected
ROS_PLUG="ros-${ROS_DISTRO}-ros-base"

if ! snapctl is-connected ${ROS_PLUG}; then
    log_and_echo "Plug '${ROS_PLUG}' isn't connected. Please run:"
    log_and_echo "snap connect ${SNAP_NAME}:${ROS_PLUG} ${ROS_PLUG}:${ROS_PLUG}"
    exit 1
fi

mv "${ROS_ENV_FILE}.tmp" "${ROS_ENV_FILE}"
# Combine all lines into a single line and write to the final file
tr '\n' ' ' < "${ROS_SNAP_ARGS}.tmp" | sed 's/ $/\n/' > "${ROS_SNAP_ARGS}"

# Define the path for the manage_ros_env.sh script
MANAGE_SCRIPT="${SNAP_COMMON}/manage_ros_env.sh"

# Create the manage_ros_env.sh script in ${SNAP_COMMON}
cat << EOF > "${MANAGE_SCRIPT}"
#!/bin/bash

ROS_ENV_FILE="${SNAP_COMMON}/ros.env"
SOURCE_LINE="source \${ROS_ENV_FILE}"

add_source_to_bashrc() {
  if ! grep -Fxq "\$SOURCE_LINE" ~/.bashrc; then
    echo "\$SOURCE_LINE" >> ~/.bashrc
    echo "Added '\$SOURCE_LINE' to ~/.bashrc"
  else
    echo "'\$SOURCE_LINE' is already in ~/.bashrc"
  fi
}

remove_source_from_bashrc() {
  sed -i "\|\$SOURCE_LINE|d" ~/.bashrc
  echo "Removed '\$SOURCE_LINE' from ~/.bashrc"
}

case "\$1" in
  remove)
    remove_source_from_bashrc
    ;;
  add|*)
    add_source_to_bashrc
    ;;
esac
EOF

# Make the manage_ros_env.sh script executable
chmod +x "${MANAGE_SCRIPT}"

