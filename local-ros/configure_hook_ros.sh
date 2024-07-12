#!/bin/bash -e

# The configure hook is called every time one the following actions happen:
# - initial snap installation
# - snap refresh
# - whenever the user runs snap set|unset to change a configuration option

# Define a function to log and echo messages
source $SNAP/usr/bin/utils.sh

# Function to check the type of the provided XML file
check_xml_profile_type() {
    local xml_file="$1"

    if [[ ! -f "$xml_file" ]]; then
        log_and_echo "File '$xml_file' does not exist."
        return 1
    fi

    local root_element
    local namespace

    # Extract the root element
    root_element=$(yq '. | keys | .[1]' "$xml_file")

    # Extract the namespace based on the root element
    if [[ "$root_element" == "CycloneDDS" ]]; then
        namespace=$(yq .CycloneDDS."+@xmlns" "$xml_file")
    elif [[ "$root_element" == "profiles" ]]; then
        namespace=$(yq .profiles."+@xmlns" "$xml_file")
    else
        namespace="unknown"
    fi

    # Remove quotes from the extracted values
    root_element=${root_element//\"/}
    namespace=${namespace//\"/}

    if [[ "$root_element" == "profiles" ]] && [[ "$namespace" == "http://www.eprosima.com/XMLSchemas/fastRTPS_Profiles" ]]; then
        echo "rmw_fastrtps_cpp"
    elif [[ "$root_element" == "CycloneDDS" ]] && [[ "$namespace" == "https://cdds.io/config" ]]; then
        echo "rmw_cyclonedds_cpp"
    else
        exit 1
    fi
}

VALID_ROS_KEYS=("localhost-only" "domain-id" "transport" "namespace")

# Call the validation function
validate_keys "ros" VALID_ROS_KEYS[@]

ROS_LOCALHOST_ONLY="$(snapctl get ros.localhost-only)"
ROS_DOMAIN_ID="$(snapctl get ros.domain-id)"

# Make sure ROS_LOCALHOST_ONLY is valid
VALID_ROS_LOCALHOST_ONLY_OPTIONS=(1 0)
validate_option "ros.localhost-only" VALID_ROS_LOCALHOST_ONLY_OPTIONS[@]

# Make sure ROS_DOMAIN_ID is valid
# Make sure WEBUI_PORT is valid
SUPPORTED_RANGE=(0 232)
# Validate a specific port, for example, webui.port
validate_number "ros.domain-id" SUPPORTED_RANGE[@]

# Get the ros.transport setting using snapctl
OPT="ros.transport"
TRANSPORT_SETTING="$(snapctl get ${OPT})"

# Check if TRANSPORT_SETTING is "builtin"
if [ "$TRANSPORT_SETTING" == "builtin" ]; then
  # Change the value to "rmw_fastrtps_cpp"
  TRANSPORT_SETTING="rmw_fastrtps_cpp"
fi

# Only exit with status 1 if conditions are not met
if [ "$TRANSPORT_SETTING" != "rmw_fastrtps_cpp" ] && [ "$TRANSPORT_SETTING" != "rmw_cyclonedds_cpp" ] && [ ! -f "${SNAP_COMMON}/${TRANSPORT_SETTING}.xml" ]; then
  log_and_echo "'${SNAP_COMMON}/${TRANSPORT_SETTING}.xml' does not exist."
  exit 1
fi

if [ "$TRANSPORT_SETTING" = "rmw_fastrtps_cpp" ] || [ "$TRANSPORT_SETTING" = "shm" ]; then
  if ! snapctl is-connected shm-plug; then
    log_and_echo "to use 'rmw_fastrtps_cpp' and 'shm' tranport shm-plug need to be connected, please run:"
    log_and_echo "sudo snap connect ${SNAP_NAME}:shm-plug ${SNAP_NAME}:shm-slot"
    exit 1
  fi
fi

# Make sure ros-humble-ros-base is connected
ROS_PLUG="ros-humble-ros-base"

if ! snapctl is-connected ${ROS_PLUG}; then
    log_and_echo "Plug '${ROS_PLUG}' isn't connected. Please run:"
    log_and_echo "snap connect ${SNAP_NAME}:${ROS_PLUG} ${ROS_PLUG}:${ROS_PLUG}"
    exit 1
fi

# Create the ${SNAP_COMMON}/ros.env file and export variables (for bash session running ROS2)
ROS_ENV_FILE="${SNAP_COMMON}/ros.env"

# Create the ${SNAP_COMMON}/ros.env file and export variables (for bash session running ROS2)
ROS_SNAP_ARGS="${SNAP_COMMON}/ros_snap_args"

echo "export ROS_DOMAIN_ID=${ROS_DOMAIN_ID}" > "${ROS_ENV_FILE}"
echo "export ROS_LOCALHOST_ONLY=${ROS_LOCALHOST_ONLY}" >> "${ROS_ENV_FILE}"

NAMESPACE=$(snapctl get ros.namespace)

# Check if the namespace is set and not empty
if [ -n "$NAMESPACE" ]; then
  echo "ros.domain-id=${ROS_DOMAIN_ID} ros.localhost-only=${ROS_LOCALHOST_ONLY} ros.transport=${TRANSPORT_SETTING} ros.namespace=${NAMESPACE}" > "${ROS_SNAP_ARGS}"
  echo "export ROS_NAMESPACE=${NAMESPACE}" >> "${ROS_ENV_FILE}"
else
  echo "ros.domain-id=${ROS_DOMAIN_ID} ros.localhost-only=${ROS_LOCALHOST_ONLY} ros.transport=${TRANSPORT_SETTING} ros.namespace!" > "${ROS_SNAP_ARGS}"
  echo "unset ROS_NAMESPACE" >> "${ROS_ENV_FILE}"
fi

# Check the ros.transport setting and export the appropriate environment variable
if [ "$TRANSPORT_SETTING" != "rmw_fastrtps_cpp" ] && [ "$TRANSPORT_SETTING" != "rmw_cyclonedds_cpp" ]; then
    profile_type=$(check_xml_profile_type "${SNAP_COMMON}/${TRANSPORT_SETTING}.xml")
    if [[ "$profile_type" == "rmw_fastrtps_cpp" ]]; then
        echo "unset CYCLONEDDS_URI" >> "${ROS_ENV_FILE}"
        echo "export RMW_IMPLEMENTATION=${profile_type}" >> "${ROS_ENV_FILE}"
        echo "export FASTRTPS_DEFAULT_PROFILES_FILE=${SNAP_COMMON}/${TRANSPORT_SETTING}.xml" >> "${ROS_ENV_FILE}"
    elif [[ "$profile_type" == "rmw_cyclonedds_cpp" ]]; then
        echo "unset FASTRTPS_DEFAULT_PROFILES_FILE" >> "${ROS_ENV_FILE}"
        echo "export RMW_IMPLEMENTATION=${profile_type}" >> "${ROS_ENV_FILE}"
        echo "export CYCLONEDDS_URI=file://${SNAP_COMMON}/${TRANSPORT_SETTING}.xml" >> "${ROS_ENV_FILE}"
    else
        log_and_echo "'${TRANSPORT_SETTING}' is not a supported value for '${OPT}'. Possible values are: rmw_fastrtps_cpp, rmw_cyclonedds_cpp, or a valid profile XML file."
        exit 1
    fi
elif [ "$TRANSPORT_SETTING" == "rmw_fastrtps_cpp" ] || [ "$TRANSPORT_SETTING" == "rmw_cyclonedds_cpp" ]; then
  echo "unset CYCLONEDDS_URI" >> "${ROS_ENV_FILE}"
  echo "unset FASTRTPS_DEFAULT_PROFILES_FILE" >> "${ROS_ENV_FILE}"
  echo "export RMW_IMPLEMENTATION=${TRANSPORT_SETTING}" >> "${ROS_ENV_FILE}"
fi

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

