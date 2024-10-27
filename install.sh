#!/bin/sh
set -e

OWNER=${OWNER:-"idelchi"}
TOOL=${TOOL:-"example"}
PREFIX=$(printf "%s" "${TOOL}" | tr 'a-z' 'A-Z' | tr -c 'A-Z' '_')

# Allow setting via environment variables, will be overridden by flags
eval BINARY=\${${PREFIX}_BINARY:-\"${TOOL}\"}
eval VERSION=\${${PREFIX}_VERSION:-\"v0.1\"}
eval OUTPUT_DIR=\${${PREFIX}_OUTPUT_DIR:-\"./bin\"}
eval DEBUG=\${${PREFIX}_DEBUG:-0}
eval DRY_RUN=\${${PREFIX}_DRY_RUN:-0}
eval ARCH=\${${PREFIX}_ARCH:-\"\"}
eval OS=\${${PREFIX}_OS:-\"\"}

# Output formatting
format_message() {
    local color="${1}"
    local message="${2}"
    local prefix="${3}"

    # Only use colors if output is a terminal
    if [ -t 1 ]; then
        case "${color}" in
            red)    printf '\033[0;31m%s\033[0m\n' "${prefix}${message}" >&2 ;;
            yellow) printf '\033[0;33m%s\033[0m\n' "${prefix}${message}" >&2 ;;
            green)  printf '\033[0;32m%s\033[0m\n' "${prefix}${message}" ;;
            *)      printf '%s\n' "${prefix}${message}" ;;
        esac
    else
        printf '%s\n' "${prefix}${message}"
    fi
}

debug() {
    if [ "${DEBUG}" -eq 1 ]; then
        format_message "yellow" "$*" "DEBUG: "
    fi
}

warning() {
    format_message "red" "$*" "Warning: "
}

info() {
    format_message "" "$*"
}

success() {
    format_message "green" "$*"
}

# Check if a command exists
need_cmd() {
    if ! command -v "${1}" >/dev/null 2>&1; then
        warning "Required command '${1}' not found"
        exit 1
    fi
    debug "Found required command: ${1}"
}
usage() {
    # Define column widths
    local flag_width=8
    local env_width=40
    local default_width=28
    local desc_width=40

    cat <<EOF
Usage: ${0} [OPTIONS]
Installs '${BINARY}' binary by downloading from GitHub releases.

Flags and environment variables:
EOF

    # Print header with printf
    printf "%-${flag_width}s %-${env_width}s %-${default_width}s %s\n" \
        "Flag" "Env" "Default" "Description"
    printf "%s\n" "-----------------------------------------------------------------------------------------------------"

    # Print each row with printf
    printf "%-${flag_width}s %-${env_width}s %-${default_width}s %s\n" \
        "-b" "${PREFIX}_BINARY" "\"${BINARY}\"" "Binary name to install"
    printf "%-${flag_width}s %-${env_width}s %-${default_width}s %s\n" \
        "-v" "${PREFIX}_VERSION" "\"${VERSION}\"" "Version to install"
    printf "%-${flag_width}s %-${env_width}s %-${default_width}s %s\n" \
        "-d" "${PREFIX}_OUTPUT_DIR" "\"${OUTPUT_DIR}\"" "Output directory"
    printf "%-${flag_width}s %-${env_width}s %-${default_width}s %s\n" \
        "-o" "${PREFIX}_OS" "<detected>" "Override operating system"
    printf "%-${flag_width}s %-${env_width}s %-${default_width}s %s\n" \
        "-a" "${PREFIX}_ARCH" "<detected>" "Override architecture"
    printf "%-${flag_width}s %-${env_width}s %-${default_width}s %s\n" \
        "-x" "${PREFIX}_DEBUG" "" "Enable debug output"
    printf "%-${flag_width}s %-${env_width}s %-${default_width}s %s\n" \
        "-n" "${PREFIX}_DRY_RUN" "" "Dry run mode"
    printf "%-${flag_width}s %-${env_width}s %-${default_width}s %s\n" \
        "-h" "" "" "Show this help message"

    cat <<EOF

Flags take precedence over environment variables when both are set.

Example:
    ${PREFIX}_VERSION="v1.0" ./install.sh -o /usr/local/bin

Set \`-a\` or \`${PREFIX}_ARCH\` to download a specific architecture binary.
This can be useful for edge-cases such as running a 32-bit userland on a 64-bit system.

EOF
    exit 1
}
# Detect architecture with userland check
detect_arch() {
    local arch machine_arch

    machine_arch=$(uname -m)
    debug "Raw architecture: ${machine_arch}"

    case "${machine_arch}" in
        x86_64|amd64)
            # Check for 32-bit userland on 64-bit system only on Linux
            if [ "${OS}" = "linux" ] && command -v getconf >/dev/null 2>&1; then
                if [ "$(getconf LONG_BIT)" = "32" ]; then
                    warning "32-bit userland detected on 64-bit Linux system. Using 32-bit binary."
                    arch="x86"
                else
                    arch="amd64"
                fi
            else
                arch="amd64"
            fi
            ;;
        aarch64|arm64)
            # Check for 32-bit userland on 64-bit system only on Linux
            if [ "${OS}" = "linux" ] && command -v getconf >/dev/null 2>&1; then
                if [ "$(getconf LONG_BIT)" = "32" ]; then
                    warning "32-bit userland detected on 64-bit Linux system. Using armv7 binary."
                    arch="armv7"
                else
                    arch="arm64"
                fi
            else
                arch="arm64"
            fi
            ;;
        arm*)
            arch=${machine_arch%l}
            ;;
        i386|i686)
            arch="x86"
            ;;
        *)
            arch="${machine_arch}"
            ;;
    esac

    debug "Detected architecture: ${arch}"
    ARCH="${arch}"
}

# Detect OS
detect_os() {
    local os
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    debug "Raw OS: ${os}"

    case "${os}" in
        darwin)
            OS="darwin"
            ;;
        linux)
            OS="linux"
            ;;
        msys*|mingw*|cygwin*|windows*)
            OS="windows"
            ;;
        *)
            OS="${os}"
            ;;
    esac

    debug "Detected OS: ${OS}"
}

# Verify the platform is supported
verify_platform() {
    local supported="darwin_amd64 darwin_arm64 linux_amd64 linux_arm64 linux_armv6 linux_armv7 linux_x86 windows_amd64"
    local platform="${OS}_${ARCH}"
    debug "Checking platform: ${platform}"

    if ! printf '%s' "${supported}" | grep -q -w "${platform}"; then
        warning "Platform '${platform}' is not supported"
        warning "Supported platforms: ${supported}"
        exit 1
    fi

    debug "Platform '${platform}' is supported"
}

# Parse arguments
parse_args() {
    while getopts ":b:v:d:a:o:xnkh" opt; do
        case "${opt}" in
            b) BINARY="${OPTARG}" ;;
            v) VERSION="${OPTARG}" ;;
            d) OUTPUT_DIR="${OPTARG}" ;;
            a) ARCH="${OPTARG}" ;;
            o) OS="${OPTARG}" ;;
            x) DEBUG=1 ;;
            n) DRY_RUN=1 ;;
            h) usage ;;
            :) warning "Option -${OPTARG} requires an argument"; usage ;;
            *) warning "Invalid option: -${OPTARG}"; usage ;;
        esac
    done
}

# Main installation function
install() {
    local FORMAT="$1"
    local tmp code

    # Construct the download URL
    local BASE_URL BINARY_NAME URL
    BASE_URL="https://github.com/${OWNER}/${BINARY}/releases/download"
    BINARY_NAME="${BINARY}_${OS}_${ARCH}.${FORMAT}"
    URL="${BASE_URL}/${VERSION}/${BINARY_NAME}"

    # Create output directory if it doesn't exist
    mkdir -p "${OUTPUT_DIR}"

    success "Selecting '${VERSION}': '${BINARY_NAME}'"
    debug "Starting download process..."

    if [ "${DRY_RUN}" -eq 1 ]; then
        info "Would download from: '${URL}'"
        info "Would install to: '${OUTPUT_DIR}'"
        exit 0
    fi

    tmp=$(mktemp)
    trap 'rm -f "${tmp}"' EXIT

    # Download and extract/install
    success "Downloading '${BINARY_NAME}' from '${URL}'"

    code=$(curl -s -w '%{http_code}' -L -o "${tmp}" "${URL}")

    if [ "${code}" != "200" ]; then
        warning "Failed to download ${URL}: ${code}"
        exit 1
    fi

    if [ "${FORMAT}" = "tar.gz" ]; then
        tar -C "${OUTPUT_DIR}" -xzf "${tmp}"
    else
        unzip -d "${OUTPUT_DIR}" "${tmp}"
    fi

    success "'${BINARY}' installed to '${OUTPUT_DIR}'"
}

check_requirements() {
    REQUIRED_COMMANDS="
        curl
        uname
        mktemp
        mkdir
        grep
        tr
        sed
        basename
        dirname"

    for cmd in $REQUIRED_COMMANDS; do
        need_cmd "$cmd"
    done
}

check_default() {
    # If `TOOL` is example, exit with an error
    if [ "${TOOL}" = "example" ]; then
        warning "Please set the TOOL environment variable to the desired tool name"
        exit 1
    fi
}

main() {
    # Parse arguments
    parse_args "$@"

    # Check for default values
    check_default

    # Check for required commands
    check_requirements

    # Only detect OS if not manually specified
    [ -z "${OS}" ] && detect_os
    # Only detect arch if not manually specified
    [ -z "${ARCH}" ] && detect_arch
    verify_platform

    # Set the format based on the OS
    FORMAT="tar.gz"
    if [ "${OS}" = "windows" ]; then
        FORMAT="zip"
    fi

    # Check for required commands
    [ "${FORMAT}" = "tar.gz" ] && need_cmd tar
    [ "${FORMAT}" = "zip" ] && need_cmd unzip

    # Install the binary
    install "${FORMAT}"
}

main "$@"
