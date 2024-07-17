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

# Validate the TRANSPORT_SETTING
ADDITIONAL_DDS_OPTIONS=("rmw_fastrtps_cpp" "rmw_cyclonedds_cpp")

validate_config_param "ros.transport" "dds-config-VALUE.xml" ADDITIONAL_DDS_OPTIONS[@]

TRANSPORT_SETTING="$(snapctl get ros.transport)"

if [ "$TRANSPORT_SETTING" = "rmw_fastrtps_cpp" ] || [ "$TRANSPORT_SETTING" = "shm" ]; then
  if ! snapctl is-connected shm-plug; then
    log_and_echo "to use 'rmw_fastrtps_cpp' and 'shm' tranport shm-plug need to be connected, please run:"
    log_and_echo "sudo snap connect ${SNAP_NAME}:shm-plug ${SNAP_NAME}:shm-slot"
    exit 1
  fi
fi

# Check the ros.transport setting and export the appropriate environment variable
if [ "$TRANSPORT_SETTING" != "rmw_fastrtps_cpp" ] && [ "$TRANSPORT_SETTING" != "rmw_cyclonedds_cpp" ]; then
    profile_type=$(check_xml_profile_type "${SNAP_COMMON}/dds-config-${TRANSPORT_SETTING}.xml")
    if [[ "$profile_type" == "rmw_fastrtps_cpp" ]]; then
        echo "unset CYCLONEDDS_URI" >> "${ROS_ENV_FILE}.tmp"
        echo "export RMW_IMPLEMENTATION=${profile_type}" >> "${ROS_ENV_FILE}.tmp"
        echo "export FASTRTPS_DEFAULT_PROFILES_FILE=${SNAP_COMMON}/dds-config-${TRANSPORT_SETTING}.xml" >> "${ROS_ENV_FILE}.tmp"
    elif [[ "$profile_type" == "rmw_cyclonedds_cpp" ]]; then
        echo "unset FASTRTPS_DEFAULT_PROFILES_FILE" >> "${ROS_ENV_FILE}.tmp"
        echo "export RMW_IMPLEMENTATION=${profile_type}" >> "${ROS_ENV_FILE}.tmp"
        echo "export CYCLONEDDS_URI=file://${SNAP_COMMON}/dds-config-${TRANSPORT_SETTING}.xml" >> "${ROS_ENV_FILE}.tmp"
    else
        log_and_echo "'${TRANSPORT_SETTING}' error: The transport setting is not valid."
        exit 1
    fi
elif [ "$TRANSPORT_SETTING" == "rmw_fastrtps_cpp" ] || [ "$TRANSPORT_SETTING" == "rmw_cyclonedds_cpp" ]; then
  echo "unset CYCLONEDDS_URI" >> "${ROS_ENV_FILE}.tmp"
  echo "unset FASTRTPS_DEFAULT_PROFILES_FILE" >> "${ROS_ENV_FILE}.tmp"
  echo "export RMW_IMPLEMENTATION=${TRANSPORT_SETTING}" >> "${ROS_ENV_FILE}.tmp"
fi

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

