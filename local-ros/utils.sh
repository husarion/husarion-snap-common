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

# Function to check for --allow-unset in arguments and remove it
check_and_remove_allow_unset() {
    local args=("$@")
    local allow_unset=false

    for i in "${!args[@]}"; do
        if [ "${args[$i]}" == "--allow-unset" ]; then
            allow_unset=true
            unset 'args[$i]'
            break
        fi
    done

    # Return modified arguments and allow_unset flag
    echo "${args[@]}"
    $allow_unset && return 0 || return 1
}

# Function to validate the option values
validate_option() {
    local args=("$@")
    local allow_unset=false

    # Check for --allow-unset and remove it from arguments
    set -- $(check_and_remove_allow_unset "${args[@]}") && allow_unset=true

    local OPT="$1"
    local VALID_OPTIONS=("${!2}")

    VALUE="$(snapctl get ${OPT})"

    if $allow_unset && [ -z "$VALUE" ]; then
        return 0
    fi

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
    local args=("$@")
    local allow_unset=false

    # Check for --allow-unset and remove it from arguments
    set -- $(check_and_remove_allow_unset "${args[@]}") && allow_unset=true

    local top_level_key="$1"
    local valid_keys=("${!2}")

    # Get the current configuration keys
    local config_keys=$(snapctl get "$top_level_key" | yq '. | keys' | sed 's/- //g' | tr -d '"')

    if $allow_unset && [ -z "$config_keys" ]; then
        return 0
    fi

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
    local args=("$@")
    local allow_unset=false

    # Check for --allow-unset and remove it from arguments
    set -- $(check_and_remove_allow_unset "${args[@]}") && allow_unset=true

    local value_key="$1"
    local range=("${!2}")
    local excluded_values=("${!3:-}")

    # Get the value using snapctl
    local value=$(snapctl get "$value_key")

    if $allow_unset && [ -z "$value" ]; then
        return 0
    fi

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
    local args=("$@")
    local allow_unset=false

    # Check for --allow-unset and remove it from arguments
    set -- $(check_and_remove_allow_unset "${args[@]}") && allow_unset=true

    local value_key="$1"

    # Get the value using snapctl
    local value=$(snapctl get "$value_key")

    if $allow_unset && [ -z "$value" ]; then
        return 0
    fi

    # Check if the value is a floating-point number
    if ! [[ "$value" =~ ^-?[0-9]*\.?[0-9]+$ ]]; then
        log_and_echo "'${value}' is not a supported value for '${value_key}'. Possible values are floating-point numbers."
        exit 1
    fi
}

validate_regex() {
    local args=("$@")
    local allow_unset=false

    # Check for --allow-unset and remove it from arguments
    set -- $(check_and_remove_allow_unset "${args[@]}") && allow_unset=true

    local value_key="$1"
    local regex="$2"
    local error_message="$3"

    # Get the value using snapctl
    local value=$(snapctl get "$value_key")

    if $allow_unset && [ -z "$value" ]; then
        return 0
    fi

    # Check if the value matches the regex
    if ! [[ "$value" =~ $regex ]]; then
        log_and_echo "'${value}' is not a supported value for '${value_key}'. ${error_message}"
        exit 1
    fi
}

validate_path() {
    local args=("$@")
    local allow_unset=false

    # Check for --allow-unset and remove it from arguments
    set -- $(check_and_remove_allow_unset "${args[@]}") && allow_unset=true

    local path_key="$1"
    local regex="$2"
    shift 2
    local valid_options=("$@")

    # Get the value using snapctl
    local config_value=$(snapctl get "$path_key")

    if $allow_unset && [ -z "$config_value" ]; then
        return 0
    fi

    # Check if the value matches any of the valid options
    for option in "${valid_options[@]}"; do
        if [ "$config_value" == "$option" ]; then
            return 0
        fi
    done

    # Check if the value matches the regex pattern or is a valid file path
    if [[ ! "$config_value" =~ $regex ]] && [ ! -f "$config_value" ]; then
        log_and_echo "'${config_value}' is not a valid value for '${path_key}'. It must match the regex '${regex}', be a valid file path, or be one of the following values: ${valid_options[*]}"
        exit 1
    fi
}

# Universal function to validate configuration parameter based on regex and optional hardcoded values
validate_config_param() {
    local args=("$@")
    local allow_unset=false

    # Check for --allow-unset and remove it from arguments
    set -- $(check_and_remove_allow_unset "${args[@]}") && allow_unset=true

    local param_key="$1"
    local regex_template="$2"
    local hardcoded_values=($3) # Expecting this to be a space-separated string of values

    # Get the param-key value using snapctl
    local param_value=$(snapctl get "$param_key")

    # Check if the param_value is empty
    if $allow_unset && [ -z "$param_value" ]; then
        return 0
    fi

    # Form the regex using the param_value
    local regex=$(echo "$regex_template" | sed "s/VALUE/${param_value}/g")

    # Check if the param_value matches any of the hardcoded values
    for value in "${hardcoded_values[@]}"; do
        if [ "$param_value" == "$value" ]; then
            return 0
        fi
    done

    # Check if the file matching the regex exists in ${SNAP_COMMON}
    if ls "${SNAP_COMMON}/" | grep -qE "$regex"; then
        return 0
    else
        log_and_echo "'${param_value}' is not a valid value for '${param_key}'. It must match the regex pattern ($regex_template) or be one of the hardcoded values: ${hardcoded_values[*]}"
        exit 1
    fi
}

validate_ipv4_addr() {
    local args=("$@")
    local allow_unset=false

    # Check for --allow-unset and remove it from arguments
    set -- $(check_and_remove_allow_unset "${args[@]}") && allow_unset=true

    local value_key="$1"

    # Get the value using snapctl
    local ip_address=$(snapctl get "$value_key")
    local ip_address_regex='^(([0-9]{1,3}\.){3}[0-9]{1,3})$'

    if $allow_unset && [ -z "$ip_address" ]; then
        return 0
    fi

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
