#!/bin/bash -e

# Define a function to log and echo messages
log_and_echo() {
    local message="$1"
    local script_name=$(basename "$0")
    # Log the message with logger
    logger -t "${SNAP_NAME}" "${script_name}: $message"
    # Echo the message to standard error
    echo -e >&2 "$message"
}

log() {
    local message="$1"
    local script_name=$(basename "$0")
    # Log the message with logger
    logger -t "${SNAP_NAME}" "${script_name}: $message"
}

is_integer() {
  expr "$1" : '-\?[0-9][0-9]*$' >/dev/null 2>&1
}

# Function to validate the option values
validate_option() {
  local OPT=$1
  local VALID_OPTIONS=("${!2}")

  VALUE="$(snapctl get ${OPT})"

  # Create an associative array to check valid options
  declare -A valid_options_map
  for option in "${VALID_OPTIONS[@]}"; do
    valid_options_map["$option"]=1
  done

  # Join the valid options with newlines
  JOINED_OPTIONS=$(printf "%s\n" "${VALID_OPTIONS[@]}")

  if [ -n "${VALUE}" ]; then
    if [[ -z "${valid_options_map[$VALUE]}" ]]; then
      log_and_echo "'${VALUE}' is not a supported value for '${OPT}' parameter. Possible values are:\n${JOINED_OPTIONS}"
      exit 1
    fi
  fi
}

# Function to validate configuration keys
validate_keys() {
    local top_level_key=$1
    local valid_keys=("${!2}")

    # Get the current configuration keys
    local config_keys=$(snapctl get "$top_level_key" | yq '. | keys' | sed 's/- //g' | tr -d '"')

    # Create an associative array to check valid keys
    declare -A valid_keys_map
    for key in "${valid_keys[@]}"; do
        valid_keys_map["$key"]=1
    done

    # Join the valid options with newlines
    JOINED_OPTIONS=$(printf "%s\n" "${valid_keys[@]}")

    # Iterate over the keys in the configuration
    for key in $config_keys; do
        # Check if the key is in the list of valid keys
        if [[ -z "${valid_keys_map[$key]}" ]]; then
            log_and_echo "'${key}' is not a supported value for '${top_level_key}' key. Possible values are:\n${JOINED_OPTIONS}"
            exit 1
        fi
    done
}

validate_number() {
    local value_key=$1
    local range=("${!2}")
    local excluded_values=("${!3:-}")

    # Get the value using snapctl
    local value=$(snapctl get "$value_key")

    # Extract the min and max range values
    local min_value=${range[0]}
    local max_value=${range[1]}

    # Join the excluded values with newlines if they exist
    local joined_excluded_values
    local exclude_message
    if [ -n "$excluded_values" ]; then
        joined_excluded_values=$(printf "%s\n" "${excluded_values[@]}")
        exclude_message=" excluding:\n${joined_excluded_values[*]}"
    else
        exclude_message=""
    fi

    # Check if the value is an integer
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        log_and_echo "'${value}' is not a supported value for '${value_key}'. Possible values are integers between ${min_value} and ${max_value}.${exclude_message}"
        exit 1
    fi

    # Check if the value is in the valid range
    if [ "$value" -lt "$min_value" ] || [ "$value" -gt "$max_value" ]; then
        log_and_echo "'${value}' is not a supported value for '${value_key}'. Possible values are integers between ${min_value} and ${max_value}.${exclude_message}"
        exit 1
    fi

    # Check if the value is in the excluded list
    if [ -n "$excluded_values" ]; then
        for excluded_value in "${excluded_values[@]}"; do
            if [ "$value" -eq "$excluded_value" ]; then
                log_and_echo "'${value}' is not a supported value for '${value_key}'. Possible values are integers between ${min_value} and ${max_value}.${exclude_message}"
                exit 1
            fi
        done
    fi
}

validate_float() {
    local value_key=$1

    # Get the value using snapctl
    local value=$(snapctl get "$value_key")

    # Check if the value is a floating-point number
    if ! [[ "$value" =~ ^-?[0-9]*\.?[0-9]+$ ]]; then
        log_and_echo "'${value}' is not a supported value for '${value_key}'. Possible values are floating-point numbers."
        exit 1
    fi
}

validate_regex() {
    local value_key=$1
    local regex=$2
    local error_message=$3

    # Get the value using snapctl
    local value=$(snapctl get "$value_key")

    # Check if the value matches the regex
    if ! [[ "$value" =~ $regex ]]; then
        log_and_echo "'${value}' is not a supported value for '${value_key}'. ${error_message}"
        exit 1
    fi
}

validate_path() {
    local value_key=$1

    # Get the value using snapctl
    local config_path=$(snapctl get "$value_key")

    # Check if the path is a valid file
    if [ ! -f "$config_path" ]; then
        log_and_echo "The path specified in '$value_key' does not exist: '$config_path'."
        exit 1
    fi
}

validate_ipv4_addr() {
    local value_key=$1

    # Get the value using snapctl
    local ip_address=$(snapctl get "$value_key")
    local ip_address_regex='^(([0-9]{1,3}\.){3}[0-9]{1,3})$'

    if [[ "$ip_address" =~ $ip_address_regex ]]; then
        # Split the IP address into its parts
        IFS='.' read -r -a octets <<< "$ip_address"

        # Check each octet
        for octet in "${octets[@]}"; do
            if ((octet < 0 || octet > 255)); then
                log_and_echo "Invalid format for '$value_key'. Each part of the IPv4 address must be between 0 and 255. Received: '$ip_address'."
                exit 1
            fi
        done
    else
        log_and_echo "Invalid format for '$value_key'. Expected format: a valid IPv4 address. Received: '$ip_address'."
        exit 1
    fi
}

# Universal function to validate serial ports
validate_serial_port() {
    local port_key=$1

    # Get the port value using snapctl
    local port_value=$(snapctl get "$port_key")

    # Check if the value is "auto" or a valid serial port
    if [ "$port_value" != "auto" ] && [ ! -e "$port_value" ]; then
        log_and_echo "'${port_value}' is not a valid value for '${port_key}'. It must be 'auto' or a valid serial port in the /dev/ directory."
        exit 1
    fi
}

# Function to find the ttyUSB* device for the specified USB Vendor and Product ID
find_ttyUSB() {
  # Extract port parameter, vendor, and product ID
  PORT_PARAM="$1"
  VENDOR_ID="$2"
  PRODUCT_ID="$3"

  # Get the serial-port value using snapctl
  SERIAL_PORT=$(snapctl get "$PORT_PARAM")

  if [ "$SERIAL_PORT" == "auto" ]; then
    for device in /sys/bus/usb/devices/*; do
      if [ -f "$device/idVendor" ]; then
        current_vendor_id=$(cat "$device/idVendor")
        if [ "$current_vendor_id" == "$VENDOR_ID" ]; then
          if [ -z "$PRODUCT_ID" ] || ([ -f "$device/idProduct" ] && [ "$(cat "$device/idProduct")" == "$PRODUCT_ID" ]); then
            # Look for ttyUSB device in the subdirectories
            for subdir in "$device/"*; do
              if [ -d "$subdir" ]; then
                for tty in $(find "$subdir" -name "ttyUSB*" -print 2>/dev/null); do
                  if [ -e "$tty" ]; then
                    ttydev=$(basename "$tty")
                    echo "/dev/$ttydev"
                    return 0
                  fi
                done
              fi
            done
          fi
        fi
      fi
    done
    echo "Error: Device with ID $VENDOR_ID:${PRODUCT_ID:-*} not found."
    return 1
  else
    echo "$SERIAL_PORT"
    return 0
  fi
}