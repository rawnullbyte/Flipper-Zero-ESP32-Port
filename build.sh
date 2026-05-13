#!/usr/bin/env bash
set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_SCRIPT="${ESP_IDF_EXPORT_SCRIPT:-${HOME}/esp/esp-idf/export.sh}"

# Default State
PORT="${ESPPORT:-}"
RUN_MONITOR=0
BUILD_ONLY=0
SELECTED_BOARD=""
PARTITIONS_FILE=""
FLASH_SIZE=""

# Hardware Definitions
declare -A TARGETS=(
    ["esp32s3"]="esp32s3"
    ["generic_esp32s3_16mb"]="esp32s3"
    ["generic_esp32s3_8mb"]="esp32s3"
    ["waveshare_c6_1.9"]="esp32c6"
    ["lilygo_t_embed_cc1101"]="esp32s3"
)

declare -A NAMES=(
    ["esp32s3"]="esp32s3_generic"
    ["generic_esp32s3_16mb"]="esp32s3_generic"
    ["generic_esp32s3_8mb"]="esp32s3_generic"
    ["waveshare_c6_1.9"]="waveshare_c6_1.9"
    ["lilygo_t_embed_cc1101"]="lilygo_t_embed_cc1101"
)

declare -A DIRS=(
    ["esp32s3"]="build_s3"
    ["generic_esp32s3_16mb"]="build_generic_16mb"
    ["generic_esp32s3_8mb"]="build_generic_8mb"
    ["waveshare_c6_1.9"]="build_waveshare_c6"
    ["lilygo_t_embed_cc1101"]="build_t_embed"
)

usage() {
    cat <<EOF
Usage: $(basename "$0") --board <name> [options]
Options:
  -b, --board <name>      Board name from internal list
  --partitions <file>     Path to custom partitions CSV
  --flash-size <size>     Flash size (e.g. 8MB, 16MB)
  -p, --port <port>       Serial port for flashing
  -m, --monitor           Run monitor after flashing
  --build-only            Skip flashing and monitoring
EOF
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--board)       SELECTED_BOARD="$2"; shift 2 ;;
        --partitions)     PARTITIONS_FILE="$2"; shift 2 ;;
        --flash-size)     FLASH_SIZE="$2"; shift 2 ;;
        -p|--port)        PORT="$2"; shift 2 ;;
        -m|--monitor)     RUN_MONITOR=1; shift ;;
        --build-only)     BUILD_ONLY=1; shift ;;
        -h|--help)        usage; exit 0 ;;
        *) echo "Unknown: $1"; usage; exit 1 ;;
    esac
done

# Validation
if [[ -z "${NAMES[$SELECTED_BOARD]:-}" ]]; then
    echo "Error: '$SELECTED_BOARD' is not a valid board." >&2
    echo "Supported: ${!NAMES[*]}"
    exit 1
fi

BOARD="${NAMES[$SELECTED_BOARD]}"
BUILD_DIR="${DIRS[$SELECTED_BOARD]}"
TARGET="${TARGETS[$SELECTED_BOARD]}"

# Force environment to match board target
export IDF_TARGET="${TARGET}"

# Source IDF Environment
[[ ! -f "${EXPORT_SCRIPT}" ]] && echo "IDF export script missing at ${EXPORT_SCRIPT}" >&2 && exit 1
# shellcheck source=/dev/null
source "${EXPORT_SCRIPT}"

cd "${SCRIPT_DIR}"

# Clean existing sdkconfig if it doesn't match the current target
if [[ -f "sdkconfig" ]]; then
    CURRENT_TARGET=$(grep "CONFIG_IDF_TARGET=" sdkconfig | cut -d'"' -f2 || echo "")
    if [[ "${CURRENT_TARGET}" != "${TARGET}" ]]; then
        echo "Target mismatch ($CURRENT_TARGET -> $TARGET), removing sdkconfig..."
        rm -f sdkconfig
    fi
fi

# Set target (Initializes build directory)
idf.py -B "${BUILD_DIR}" set-target "${TARGET}"

# Build Command Construction
COMMANDS=("reconfigure" "build")
PY_OPTS=("-B" "${BUILD_DIR}" "-DFLIPPER_BOARD=${BOARD}")

# Inject Partition Table and Flash Size via CMake
if [[ -n "${PARTITIONS_FILE}" ]]; then
    PY_OPTS+=("-DCONFIG_PARTITION_TABLE_CUSTOM=y")
    PY_OPTS+=("-DCONFIG_PARTITION_TABLE_CUSTOM_FILENAME=${PARTITIONS_FILE}")
fi

if [[ -n "${FLASH_SIZE}" ]]; then
    # Ensures the binary is compiled with correct flash size awareness
    PY_OPTS+=("-DCONFIG_ESPTOOLPY_FLASHSIZE_${FLASH_SIZE}=y")
fi

if [[ "${BUILD_ONLY}" -eq 0 ]]; then
    COMMANDS+=("flash")
    [[ -n "${PORT}" ]] && PY_OPTS+=("-p" "${PORT}")
    [[ "${RUN_MONITOR}" -eq 1 ]] && COMMANDS+=("monitor")
fi

# Run Build
idf.py "${PY_OPTS[@]}" "${COMMANDS[@]}"