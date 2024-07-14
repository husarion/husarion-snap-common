#!/bin/bash -e

# Define a function to log and echo messages
log_and_echo() {
    local message="$*"
    local script_name=$(basename "$0")
    # Log the message with logger
    logger -t "${SNAP_NAME}" "${script_name}: $message"
    # Echo the message to standard error
    echo -e "$message" >&2
}

log() {
    local message="$*"
    local script_name=$(basename "$0")
    # Log the message with logger
    logger -t "${SNAP_NAME}" "${script_name}: $message"
}

is_integer() {
  expr "$1" : '-\?[0-9][0-9]*$' >/dev/null 2>&1
}

process_args() {
    allow_unset=false
    additional_args=()

    for arg in "$@"; do
        if [ "$arg" == "--allow-unset" ]; then
            allow_unset=true
        else
            additional_args+=("$arg")
        fi
    done

    # Return results
    echo "$allow_unset"
    echo "${additional_args[@]}"
}

# Function to validate the option values
validate_option() {
    local input=($(process_args "$@"))
    local allow_unset="${input[0]}"
    local args=("${input[@]:1}")

    local opt="${args[0]}"
    local valid_options=("${!args[1]}")

    local value="$(snapctl get ${opt})"

    if [ -z "$value" ]; then
        if $allow_unset; then
            return 0
        else
            log_and_echo "'${opt}' cannot be unset."
            exit 1
        fi
    fi

    # Create an associative array to check valid options
    declare -A valid_options_map
    for option in "${valid_options[@]}"; do
        valid_options_map["$option"]=1
    done

    # Join the valid options with newlines
    local joined_options=$(printf "%s\n" "${valid_options[@]}")

    if [ -n "${value}" ]; then
        if [[ -z "${valid_options_map[$value]}" ]]; then
            log_and_echo "'${value}' is not a supported value for '${OPT}' parameter. Possible values are:\n${joined_options}"
            exit 1
        fi
    fi
}

# Function to validate configuration keys
validate_keys() {
    local input=($(process_args "$@"))
    local allow_unset="${input[0]}"
    local args=("${input[@]:1}")

    local top_level_key="${args[0]}"
    local valid_keys=("${!args[1]}")

    # Get the current configuration for the top-level key
    local config=$(snapctl get "$top_level_key")

    # Check if the top-level key is set to a non-object value
    if ! $(echo "$config" | yq 'type == "!!map"'); then
        log_and_echo "'${top_level_key}' must be an object with valid subkeys. Setting a value directly to '${top_level_key}' is not allowed."
        exit 1
    fi

    # Get the current configuration keys
    local config_keys=$(echo "$config" | yq '. | keys' | sed 's/- //g' | tr -d '"')

    if [ -z "$config_keys" ] || [ "$config_keys" == "[]" ]; then
        if $allow_unset; then
            return 0
        else
            log_and_echo "'${top_level_key}' cannot be unset."
            exit 1
        fi
    fi

    # Create an associative array to check valid keys
    declare -A valid_keys_map
    for key in "${valid_keys[@]}"; do
        valid_keys_map["$key"]=1
    done

    # Join the valid options with newlines
    local joined_options=$(printf "%s\n" "${valid_keys[@]}")

    # Iterate over the keys in the configuration
    for key in $config_keys; do
        # Check if the key is in the list of valid keys
        if [[ -z "${valid_keys_map[$key]}" ]]; then
            log_and_echo "'${key}' is not a supported value for '${top_level_key}' key. Possible values are:\n${joined_options}"
            exit 1
        fi
    done
}

validate_number() {
    local input=($(process_args "$@"))
    local allow_unset="${input[0]}"
    local args=("${input[@]:1}")

    local value_key="${args[0]}"
    local range=("${!args[1]}")
    local excluded_values=("${!args[2]:-}")

    # Get the value using snapctl
    local value=$(snapctl get "$value_key")

    if [ -z "$value" ]; then
        if $allow_unset; then
            return 0
        else
            log_and_echo "'${opt}' cannot be unset."
            exit 1
        fi
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
        log_and_echo "'${value}' is not a supported value for '${value_key}'. Possible values are integers between ${min_value} and ${max_value}. ${exclude_message}"
        exit 1
    fi

    # Check if the value is in the valid range
    if [ "$value" -lt "$min_value" ] || [ "$value" -gt "$max_value" ]; then
        log_and_echo "'${value}' is not a supported value for '${value_key}'. Possible values are integers between ${min_value} and ${max_value}. ${exclude_message}"
        exit 1
    fi

    # Check if the value is in the excluded list
    if [ -n "$excluded_values" ]; then
        for excluded_value in "${excluded_values[@]}"; do
            if [ "$value" -eq "$excluded_value" ]; then
                log_and_echo "'${value}' is not a supported value for '${value_key}'. Possible values are integers between ${min_value} and ${max_value}. ${exclude_message}"
                exit 1
            fi
        done
    fi
}

validate_float() {
    local input=($(process_args "$@"))
    local allow_unset="${input[0]}"
    local args=("${input[@]:1}")

    local value_key="${args[0]}"

    # Get the value using snapctl
    local value=$(snapctl get "$value_key")

    if [ -z "$value" ]; then
        if $allow_unset; then
            return 0
        else
            log_and_echo "'${value_key}' cannot be unset."
            exit 1
        fi
    fi

    # Check if the value is a floating-point number
    if ! [[ "$value" =~ ^-?[0-9]*\.?[0-9]+$ ]]; then
        log_and_echo "'${value}' is not a supported value for '${value_key}'. Possible values are floating-point numbers."
        exit 1
    fi
}

validate_regex() {
    local input=($(process_args "$@"))
    local allow_unset="${input[0]}"
    local args=("${input[@]:1}")

    local value_key="${args[0]}"
    local regex="${args[1]}"

    # Get the value using snapctl
    local value=$(snapctl get "$value_key")

    if [ -z "$value" ]; then
        if $allow_unset; then
            return 0
        else
            log_and_echo "'${value_key}' cannot be unset."
            exit 1
        fi
    fi

    # Check if the value matches the regex
    if ! [[ "$value" =~ $regex ]]; then
        log_and_echo "'${value}' is not a supported value for '${value_key}'. It must match the regex pattern: ${regex}"
        exit 1
    fi
}

validate_path() {
    local input=($(process_args "$@"))
    local allow_unset="${input[0]}"
    local args=("${input[@]:1}")

    local path_key="${args[0]}"
    local regex="${args[1]}"
    local valid_options=("${!args[2]:-}")

    # Get the value using snapctl
    local config_value=$(snapctl get "$path_key")

    if [ -z "$config_value" ]; then
        if $allow_unset; then
            return 0
        else
            log_and_echo "'${path_key}' cannot be unset."
            exit 1
        fi
    fi

    # Check if the value matches any of the valid options
    for option in "${valid_options[@]}"; do
        if [ "$config_value" == "$option" ]; then
            return 0
        fi
    done

    # Check if the value matches the regex pattern or is a valid file path
    if [[ ! "$config_value" =~ $regex ]] && [ ! -f "$config_value" ]; then
        log_and_echo "'${config_value}' is not a valid value for '${path_key}'. It must match the regex '${regex}', be a valid file path, or be one of the following values: ${valid_options[@]}"
        exit 1
    fi
}

# Universal function to validate configuration parameter based on regex and optional hardcoded values
validate_config_param() {
    local input=($(process_args "$@"))
    local allow_unset="${input[0]}"
    local args=("${input[@]:1}")

    local param_key="${args[0]}"
    local regex_template="${args[1]}"
    local hardcoded_values=("${!args[2]:-}")

    # Get the param-key value using snapctl
    local param_value=$(snapctl get "$param_key")

    # Check if the param_value is empty
    if [ -z "$param_value" ]; then
        if $allow_unset; then
            return 0
        else
            log_and_echo "'${param_key}' cannot be unset."
            exit 1
        fi
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
        log_and_echo "'${param_value}' is not a valid value for '${param_key}'. There is no '${SNAP_COMMON}/$regex' file and it is not one of the hardcoded values\n${hardcoded_values[@]}"
        exit 1
    fi
}

validate_ipv4_addr() {
    local input=($(process_args "$@"))
    local allow_unset="${input[0]}"
    local args=("${input[@]:1}")

    local value_key="${args[0]}"

    # Get the value using snapctl
    local ip_address=$(snapctl get "$value_key")
    local ip_address_regex='^(([0-9]{1,3}\.){3}[0-9]{1,3})$'

    if [ -z "$ip_address" ]; then
        if $allow_unset; then
            return 0
        else
            log_and_echo "'${value_key}' cannot be unset."
            exit 1
        fi
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
    local args=("$@")
    local port_param="${args[0]}"
    local vendor_id="${args[1]}"
    local product_id="${args[2]}"

    # Get the serial-port value using snapctl
    local serial_port=$(snapctl get "$port_param")

    if [ "$serial_port" == "auto" ]; then
        for device in /sys/bus/usb/devices/*; do
            if [ -f "$device/idVendor" ]; then
                current_vendor_id=$(cat "$device/idVendor")
                if [ "$current_vendor_id" == "$vendor_id" ];then
                    if [ -z "$product_id" ] || ([ -f "$device/idProduct" ] && [ "$(cat "$device/idProduct")" == "$product_id" ]); then
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
        echo "Error: Device with ID $vendor_id:${product_id:-*} not found."
        return 1
    else
        echo "$serial_port"
        return 0
    fi
}
