#!/usr/bin/env bash
# ==============================================================================
# Moto Camera Restored — Universal Recovery Package Compiler (Linux)
# Modular Multi-Generation Motorola Camera Restoration Toolkit
#
# Supported Camera Eras:
#   * Moto Camera 4 (Working — template active)
#   * Moto Camera 5 (In Development)
#   * Moto Camera 3 (Planned)
#   * Moto Camera 2 (Planned)
#
# Target Systems: LineageOS, AOSP, and custom ROMs (Android 13 - 17+)
#
# Automatically detects:
#   * Device Codename, Marketing Model, Hardware Platform / SoC
#   * Android OS Version, API SDK Level, Stock Firmware Build ID
#   * Installed Moto Camera generation & component layout
#   * Companion services (AI Scene Engine, ImagerTuning, Desktop Mode)
#   * Vendor camera HALs, HIDL/AIDL daemons, and VINTF manifests
#   * Multi-camera sensor configuration and auxiliary camera system properties
#
# Generates:
#   MotoCameraRestored_<Codename>_Recovery_Installer.zip (Lineage Recovery / TWRP sideload)
#   with LineageOS addon.d OTA backup survival script
#
# Usage:
#   Interactive:  ./compile_recovery_package_linux.sh
#   CLI:          ./compile_recovery_package_linux.sh "/path/to/stock_firmware" [output_dir] [template_dir]
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_OUTPUT_DIR="${SCRIPT_DIR}/output"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/vrwindsor1/Moto-Camera-Restored/main"

# Global state for trap cleanup
WORK_DIR=""
MOUNTED_DIRS=()

# Styling
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[32m"
C_CYAN="\033[36m"
C_YELLOW="\033[33m"
C_RED="\033[31m"
C_PURPLE="\033[35m"
C_BLUE="\033[34m"

log_info()    { echo -e "${C_CYAN}[INFO]${C_RESET} $1"; }
log_ok()      { echo -e "${C_GREEN}[OK]${C_RESET} $1"; }
log_warn()    { echo -e "${C_YELLOW}[WARN]${C_RESET} $1"; }
log_err()     { echo -e "${C_RED}[ERROR]${C_RESET} $1"; }
log_profile() { echo -e "${C_PURPLE}[PROFILE]${C_RESET} $1"; }

banner() {
  echo -e "${C_BOLD}${C_CYAN}"
  echo "================================================================================"
  echo "        Moto Camera Restored — Universal Recovery Package Compiler              "
  echo "         Modular Dynamic Multi-Generation Camera Extraction Toolkit             "
  echo "================================================================================"
  echo -e "${C_PURPLE}              ⚡ Pair Programmed with Google DeepMind Antigravity               ${C_RESET}"
  echo -e "${C_BOLD}${C_CYAN}================================================================================${C_RESET}"
  echo ""
}

# ------------------------------------------------------------------------------
# 0. Environment Setup (Ensure tools in PATH even under sudo)
# ------------------------------------------------------------------------------
setup_environment() {
  if [ -n "$SUDO_USER" ]; then
    local real_home
    real_home=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
    if [ -n "$real_home" ] && [ -d "$real_home" ]; then
      export PATH="${real_home}/.local/bin:${PATH}"
      export LD_LIBRARY_PATH="${real_home}/.local/lib:${LD_LIBRARY_PATH}"
    fi
  fi

  export PATH="${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:${PATH}"
  export LD_LIBRARY_PATH="${HOME}/.local/lib:${LD_LIBRARY_PATH}"
}

# ------------------------------------------------------------------------------
# 1. Dependency Verification
# ------------------------------------------------------------------------------
check_dependencies() {
  log_info "Verifying host build tools..."
  local missing=()

  for tool in zip simg2img lpunpack; do
    if ! command -v "$tool" &>/dev/null; then
      missing+=("$tool")
    fi
  done

  # Verify EROFS extraction capability:
  local erofs_capable=0
  if command -v erofs-extract &>/dev/null; then
    erofs_capable=1
  elif command -v fsck.erofs &>/dev/null; then
    erofs_capable=1
  elif [ "$(id -u)" -eq 0 ] && modinfo erofs &>/dev/null; then
    erofs_capable=1
  fi

  if [ "$erofs_capable" -eq 0 ]; then
    missing+=("erofs-utils (fsck.erofs / erofs-extract)")
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    log_err "Missing required build tools: ${missing[*]}"
    echo ""
    echo "Please install dependencies for your distribution:"
    echo "  Fedora / RHEL:   sudo dnf install android-tools erofs-utils zip curl python3"
    echo "  Ubuntu / Debian: sudo apt install android-sdk-libsparse-utils erofs-utils zip curl python3"
    echo "  Arch Linux:      sudo pacman -S android-tools erofs-utils zip curl python"
    echo ""
    exit 1
  fi

  log_ok "All required host build tools are available."
}

# ------------------------------------------------------------------------------
# 2. Firmware Input Resolution
# ------------------------------------------------------------------------------
get_firmware_path() {
  local input="$1"

  if [ -z "$input" ]; then
    echo -e "${C_BOLD}Please specify the path to your downloaded Motorola stock firmware:${C_RESET}"
    echo "  (Accepts: folder with sparsechunks, partition .img files, pre-extracted folders, or .zip archive)"
    echo -e "${C_CYAN}  Tip: Stock firmware can be obtained via Motorola Rescue and Smart Assistant (RSA)${C_RESET}"
    echo -e "       or from official mirrors: ${C_YELLOW}https://mirrors.lolinet.com/firmware/lenomola/${C_RESET}"
    echo ""
    read -e -p "> Path: " input
  fi

  # Trim whitespace
  input="$(echo "$input" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  # Strip surrounding quotes safely
  while [[ "$input" =~ ^[\'\"](.*)[\'\"]$ ]]; do
    input="${BASH_REMATCH[1]}"
    input="$(echo "$input" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  done

  # Expand tilde
  input="${input/#\~/$HOME}"

  if [ ! -e "$input" ]; then
    log_err "Specified path does not exist: $input"
    exit 1
  fi

  FIRMWARE_INPUT="$input"
  log_ok "Firmware source: $FIRMWARE_INPUT"
}

# ------------------------------------------------------------------------------
# 3. Extraction Engine
# ------------------------------------------------------------------------------
extract_firmware() {
  local src="$1"
  local work_dir="$2"
  local partitions_dir="${work_dir}/partitions"
  local extracted_dir="${work_dir}/extracted"

  mkdir -p "$partitions_dir" "$extracted_dir"

  # Case A: Pre-extracted directory with product/ and system_ext/
  if [ -d "$src" ] && [ -d "${src}/product" ] && [ -d "${src}/system_ext" ]; then
    log_info "Detected pre-extracted partition filesystem tree."
    FIRMWARE_ROOT="$src"
    return 0
  fi

  # Case B: If input is an archive, extract it first
  if [ -f "$src" ] && [[ "$src" =~ \.(zip|tar\.gz|tgz)$ ]]; then
    log_info "Unpacking firmware archive..."
    local unzipped_dir="${work_dir}/unpacked_zip"
    mkdir -p "$unzipped_dir"
    if [[ "$src" =~ \.zip$ ]]; then
      unzip -q "$src" -d "$unzipped_dir"
    else
      tar -xzf "$src" -C "$unzipped_dir"
    fi
    src="$unzipped_dir"
  fi

  # Case C: Check for super.img_sparsechunk.*
  local sparse_files=()
  while IFS= read -r -d $'\0' f; do
    [ -n "$f" ] && sparse_files+=("$f")
  done < <(find "$src" -maxdepth 1 -name "super.img_sparsechunk.*" -print0 2>/dev/null | sort -z -V)

  if [ ${#sparse_files[@]} -gt 0 ]; then
    log_info "Recombining ${#sparse_files[@]} super sparsechunk segments with simg2img..."
    simg2img "${sparse_files[@]}" "${work_dir}/super.raw.img"
    log_ok "Unpacking dynamic partitions from super.raw.img with lpunpack..."
    lpunpack "${work_dir}/super.raw.img" "$partitions_dir"
    rm -f "${work_dir}/super.raw.img"
  elif [ -f "${src}/super.img" ] || [ -f "${src}/super.raw.img" ]; then
    local super_img="${src}/super.img"
    [ ! -f "$super_img" ] && super_img="${src}/super.raw.img"
    log_info "Found super partition image: $super_img"
    lpunpack "$super_img" "$partitions_dir"
  elif [ -f "${src}/product.img" ] || [ -f "${src}/product_a.img" ]; then
    log_info "Found existing partition images in directory."
    partitions_dir="$src"
  else
    # Check one subdirectory deep (common for extracted LMSA/RSA downloads)
    local sub_sparse=()
    while IFS= read -r -d $'\0' f; do
      [ -n "$f" ] && sub_sparse+=("$f")
    done < <(find "$src" -mindepth 2 -maxdepth 2 -name "super.img_sparsechunk.*" -print0 2>/dev/null | sort -z -V)

    if [ ${#sub_sparse[@]} -gt 0 ]; then
      log_info "Found ${#sub_sparse[@]} sparsechunks in subdirectory. Recombining..."
      simg2img "${sub_sparse[@]}" "${work_dir}/super.raw.img"
      lpunpack "${work_dir}/super.raw.img" "$partitions_dir"
      rm -f "${work_dir}/super.raw.img"
    else
      log_err "Could not identify recognized stock firmware files in: $src"
      log_err "Expected: super.img_sparsechunk.*, super.img, or partition images (product.img, etc.)"
      exit 1
    fi
  fi

  # Extract partition images (EROFS or EXT4)
  for part in product system_ext system vendor odm; do
    local img=""
    for candidate in "${partitions_dir}/${part}_a.img" "${partitions_dir}/${part}.img" "${partitions_dir}/${part}_b.img"; do
      if [ -f "$candidate" ]; then
        img="$candidate"
        break
      fi
    done

    # odm is optional; others are mandatory
    if [ -z "$img" ]; then
      if [ "$part" = "odm" ]; then
        continue
      fi
      log_err "Missing required partition image: ${part}.img"
      exit 1
    fi

    local target_part_dir="${extracted_dir}/${part}"
    mkdir -p "$target_part_dir"

    log_info "Extracting ${part} partition (${img##*/})..."
    local extracted=0

    # Strategy 1: Loop mount if root
    if [ "$(id -u)" -eq 0 ]; then
      if mount -t erofs -o loop,ro "$img" "$target_part_dir" 2>/dev/null || mount -t ext4 -o loop,ro "$img" "$target_part_dir" 2>/dev/null; then
        MOUNTED_DIRS+=("$target_part_dir")
        extracted=1
        log_ok "Mounted ${part} partition via kernel loop."
      fi
    fi

    # Strategy 2: erofs-extract or fsck.erofs
    if [ "$extracted" -eq 0 ]; then
      if command -v erofs-extract &>/dev/null; then
        erofs-extract --extract="$target_part_dir" --overwrite "$img" 2>/dev/null || true
      elif command -v fsck.erofs &>/dev/null; then
        fsck.erofs --extract="$target_part_dir" --overwrite "$img" 2>/dev/null || true
      fi

      if [ -n "$(ls -A "$target_part_dir" 2>/dev/null)" ]; then
        extracted=1
      fi
    fi

    if [ "$extracted" -eq 0 ]; then
      log_err "Failed to extract ${part} partition (${img##*/})!"
      log_err "Please verify that erofs-utils is installed (sudo dnf install erofs-utils / sudo apt install erofs-utils)."
      exit 1
    fi
  done

  FIRMWARE_ROOT="$extracted_dir"
  log_ok "All partitions successfully extracted to: $FIRMWARE_ROOT"
}

# ------------------------------------------------------------------------------
# 4. Device Auto-Detection & Firmware Profiling
# ------------------------------------------------------------------------------
read_prop() {
  local key="$1"
  shift
  for file in "$@"; do
    if [ -f "$file" ]; then
      local val
      val=$(grep -E "^${key}=" "$file" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '\r')
      if [ -n "$val" ]; then
        echo "$val"
        return 0
      fi
    fi
  done
  return 1
}

profile_device() {
  local src_root="$1"
  log_info "Profiling device hardware and firmware properties..."

  local sys_path="${src_root}/system"
  [ -d "${src_root}/system/system" ] && sys_path="${src_root}/system/system"

  PROP_FILES=(
    "${src_root}/product/etc/build.prop"
    "${src_root}/product/build.prop"
    "${src_root}/vendor/build.prop"
    "${sys_path}/build.prop"
    "${src_root}/system_ext/etc/build.prop"
    "${src_root}/system_ext/build.prop"
    "${src_root}/odm/etc/build.prop"
  )

  DEVICE_CODENAME=$(read_prop "ro.product.vendor.device" "${PROP_FILES[@]}" || \
                   read_prop "ro.product.system.device" "${PROP_FILES[@]}" || \
                   read_prop "ro.product.product.device" "${PROP_FILES[@]}" || \
                   read_prop "ro.product.device" "${PROP_FILES[@]}" || \
                   read_prop "ro.product.vendor.name" "${PROP_FILES[@]}" || \
                   read_prop "ro.product.system.name" "${PROP_FILES[@]}" || \
                   read_prop "ro.product.product.name" "${PROP_FILES[@]}" || \
                   read_prop "ro.product.name" "${PROP_FILES[@]}" || echo "")

  # Fallback: scan product/etc/permissions/com.motorola.camera3.*.xml or camera.*.xml
  if [ -z "$DEVICE_CODENAME" ] || [ "$DEVICE_CODENAME" = "msi" ]; then
    local cam_perm
    cam_perm=$(find "${src_root}/product/etc/permissions" -name "com.motorola.camera*.*.xml" 2>/dev/null | head -n1)
    if [ -n "$cam_perm" ]; then
      local base="${cam_perm##*/}"
      local extracted_code="${base#com.motorola.camera*.}"
      extracted_code="${extracted_code%.xml}"
      if [ "$extracted_code" != "content.ai" ] && [ "$extracted_code" != "lens" ]; then
        DEVICE_CODENAME="$extracted_code"
      fi
    fi
  fi

  [ -z "$DEVICE_CODENAME" ] && DEVICE_CODENAME="generic"

  DEVICE_MODEL=$(read_prop "ro.product.product.model" "${PROP_FILES[@]}" || \
                 read_prop "ro.product.system.model" "${PROP_FILES[@]}" || \
                 read_prop "ro.product.vendor.model" "${PROP_FILES[@]}" || \
                 read_prop "ro.product.model" "${PROP_FILES[@]}" || echo "Motorola Smartphone")

  ANDROID_VERSION=$(read_prop "ro.build.version.release" "${PROP_FILES[@]}" || \
                    read_prop "ro.product.build.version.release" "${PROP_FILES[@]}" || \
                    read_prop "ro.system.build.version.release" "${PROP_FILES[@]}" || echo "14")

  SDK_LEVEL=$(read_prop "ro.build.version.sdk" "${PROP_FILES[@]}" || \
              read_prop "ro.product.build.version.sdk" "${PROP_FILES[@]}" || \
              read_prop "ro.system.build.version.sdk" "${PROP_FILES[@]}" || echo "34")

  BUILD_ID=$(read_prop "ro.build.id" "${PROP_FILES[@]}" || \
             read_prop "ro.product.build.id" "${PROP_FILES[@]}" || \
             read_prop "ro.system.build.id" "${PROP_FILES[@]}" || echo "UNKNOWN")

  PLATFORM_SOC=$(read_prop "ro.board.platform" "${PROP_FILES[@]}" || \
                 read_prop "ro.hardware" "${PROP_FILES[@]}" || \
                 read_prop "ro.product.board" "${PROP_FILES[@]}" || echo "unknown")

  log_profile "Detected Stock Firmware Profile:"
  echo -e "    ${C_BOLD}Model:${C_RESET}       ${DEVICE_MODEL}"
  echo -e "    ${C_BOLD}Codename:${C_RESET}    ${DEVICE_CODENAME}"
  echo -e "    ${C_BOLD}Platform:${C_RESET}    ${PLATFORM_SOC}"
  echo -e "    ${C_BOLD}Android:${C_RESET}     ${ANDROID_VERSION} (API SDK ${SDK_LEVEL})"
  echo -e "    ${C_BOLD}Build ID:${C_RESET}    ${BUILD_ID}"
}

# ------------------------------------------------------------------------------
# 5. Modular Camera Generation Detection
# ------------------------------------------------------------------------------
detect_camera_generation() {
  local src_root="$1"
  log_info "Detecting stock Motorola Camera generation and components..."

  CAMERA_GEN=""
  CAMERA_GEN_NAME=""
  CAMERA_MAIN_APK=""
  CAMERA_VER=""

  # 1. Check for Moto Camera 5 (com.motorola.camera5 / MotCamera5 / v10.x)
  local cam5_apk
  cam5_apk=$(find "$src_root" -type f \( -name "MotCamera5.apk" -o -name "*camera5*.apk" \) 2>/dev/null | head -n1)
  if [ -n "$cam5_apk" ]; then
    CAMERA_GEN="camera5"
    CAMERA_GEN_NAME="Moto Camera 5"
    CAMERA_MAIN_APK="$cam5_apk"
    CAMERA_VER="v10.x"
  fi

  # 2. Check for Moto Camera 4 (MotCamera4.apk or MotCamera3 with version 9.x)
  if [ -z "$CAMERA_GEN" ]; then
    local cam4_apk
    cam4_apk=$(find "$src_root" -type f -name "MotCamera4.apk" 2>/dev/null | head -n1)
    if [ -n "$cam4_apk" ]; then
      CAMERA_GEN="camera4"
      CAMERA_GEN_NAME="Moto Camera 4"
      CAMERA_MAIN_APK="$cam4_apk"
    fi
  fi

  # 3. Check for Moto Camera 3 (MotCamera3.apk / com.motorola.camera3)
  if [ -z "$CAMERA_GEN" ]; then
    local cam3_apk
    cam3_apk=$(find "$src_root" -type f \( -name "MotCamera3.apk" -o -name "MotCamera.apk" \) 2>/dev/null | head -n1)
    if [ -n "$cam3_apk" ]; then
      # Distinguish Camera 4 (v9.x) vs Camera 3 (v8.x/v7.x)
      local ver_check=""
      if command -v python3 &>/dev/null; then
        ver_check=$(python3 -c "
import zipfile, re, sys
try:
    with zipfile.ZipFile('$cam3_apk', 'r') as z:
        for name in ['classes.dex', 'classes2.dex']:
            if name in z.namelist():
                m = re.findall(b'9\.[0-9]+\.[0-9]+\.[0-9]+', z.read(name))
                if m:
                    print('camera4')
                    sys.exit(0)
except Exception:
    pass
print('camera3')
" 2>/dev/null || true)
      fi

      if [ "$ver_check" = "camera4" ]; then
        CAMERA_GEN="camera4"
        CAMERA_GEN_NAME="Moto Camera 4"
      else
        CAMERA_GEN="camera3"
        CAMERA_GEN_NAME="Moto Camera 3"
      fi
      CAMERA_MAIN_APK="$cam3_apk"
    fi
  fi

  # 4. Check for Moto Camera 2 (MotCamera2.apk / com.motorola.camera2)
  if [ -z "$CAMERA_GEN" ]; then
    local cam2_apk
    cam2_apk=$(find "$src_root" -type f \( -name "MotCamera2.apk" -o -name "*camera2*.apk" \) 2>/dev/null | head -n1)
    if [ -n "$cam2_apk" ]; then
      CAMERA_GEN="camera2"
      CAMERA_GEN_NAME="Moto Camera 2"
      CAMERA_MAIN_APK="$cam2_apk"
      CAMERA_VER="v7.x"
    fi
  fi

  # Fallback heuristics based on OS version
  if [ -z "$CAMERA_GEN" ]; then
    log_warn "Could not pinpoint camera APK by standard naming. Checking OS release heuristics..."
    if [ "$SDK_LEVEL" -ge 35 ]; then
      CAMERA_GEN="camera5"
      CAMERA_GEN_NAME="Moto Camera 5"
    elif [ "$SDK_LEVEL" -ge 31 ]; then
      CAMERA_GEN="camera4"
      CAMERA_GEN_NAME="Moto Camera 4"
    elif [ "$SDK_LEVEL" -ge 29 ]; then
      CAMERA_GEN="camera3"
      CAMERA_GEN_NAME="Moto Camera 3"
    else
      CAMERA_GEN="camera2"
      CAMERA_GEN_NAME="Moto Camera 2"
    fi
  fi

  # Extract detailed version string if possible
  if [ -n "$CAMERA_MAIN_APK" ] && [ -z "$CAMERA_VER" ] && command -v python3 &>/dev/null; then
    CAMERA_VER=$(python3 -c "
import zipfile, re, sys
try:
    with zipfile.ZipFile('$CAMERA_MAIN_APK', 'r') as z:
        for name in ['classes.dex', 'classes2.dex']:
            if name in z.namelist():
                m = re.findall(b'[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+', z.read(name))
                if m:
                    print(m[0].decode())
                    sys.exit(0)
except Exception:
    pass
" 2>/dev/null || true)
  fi

  [ -z "$CAMERA_VER" ] && CAMERA_VER="${CAMERA_GEN_NAME}"

  log_ok "Detected Camera Suite: ${C_BOLD}${CAMERA_GEN_NAME}${C_RESET} (${CAMERA_VER})"
  log_info "Active Template Module: ${CAMERA_GEN}"
}

# ------------------------------------------------------------------------------
# 6. Modular Template Resolution (Local or Standalone Remote Fetch)
# ------------------------------------------------------------------------------
ensure_templates() {
  local target_work_dir="$1"
  local camera_gen="$2"
  local gen_name="$3"
  local cli_template="$4"

  # 1. Check CLI specified path if provided
  if [ -n "$cli_template" ]; then
    local cli_candidate=""
    if [ -f "${cli_template}/META-INF/com/google/android/update-binary" ]; then
      cli_candidate="$cli_template"
    elif [ -f "${cli_template}/${camera_gen}/META-INF/com/google/android/update-binary" ]; then
      cli_candidate="${cli_template}/${camera_gen}"
    elif [ -f "${cli_template}/templates/${camera_gen}/META-INF/com/google/android/update-binary" ]; then
      cli_candidate="${cli_template}/templates/${camera_gen}"
    fi

    if [ -n "$cli_candidate" ]; then
      TEMPLATES_DIR="$(cd "$cli_candidate" && pwd)"
      log_ok "Using CLI-specified recovery templates from: $TEMPLATES_DIR"
      return 0
    else
      log_warn "CLI-specified template path '${cli_template}' does not contain required template files."
    fi
  fi

  local local_dir="${SCRIPT_DIR}/templates/${camera_gen}"
  local cwd_dir="$(pwd)/templates/${camera_gen}"

  # 2. Check local script directory path
  if [ -d "$local_dir" ] && [ -f "${local_dir}/META-INF/com/google/android/update-binary" ]; then
    TEMPLATES_DIR="$local_dir"
    log_ok "Found local recovery templates for ${gen_name} (${camera_gen})."
    return 0
  fi

  # 3. Check current working directory path
  if [ -d "$cwd_dir" ] && [ -f "${cwd_dir}/META-INF/com/google/android/update-binary" ]; then
    TEMPLATES_DIR="$cwd_dir"
    log_ok "Found local recovery templates for ${gen_name} (${camera_gen})."
    return 0
  fi

  # 4. Template folder not present in working directory -> Prompt the user
  log_warn "Recovery template folder for ${gen_name} ('templates/${camera_gen}') was not found in working directory."

  local user_input=""
  echo ""
  echo -e "${C_BOLD}Please point to a local template directory, or press [Enter] to automatically download from GitHub:${C_RESET}"
  if [ -t 0 ]; then
    read -e -p "> Local template path [Enter to download]: " user_input
  else
    read -r user_input || user_input=""
  fi
  user_input="$(echo "$user_input" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  while [[ "$user_input" =~ ^[\'\"](.*)[\'\"]$ ]]; do
    user_input="${BASH_REMATCH[1]}"
    user_input="$(echo "$user_input" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  done
  user_input="${user_input/#\~/$HOME}"

  if [ -n "$user_input" ]; then
    local candidate_path=""
    if [ -f "${user_input}/META-INF/com/google/android/update-binary" ]; then
      candidate_path="$user_input"
    elif [ -f "${user_input}/${camera_gen}/META-INF/com/google/android/update-binary" ]; then
      candidate_path="${user_input}/${camera_gen}"
    elif [ -f "${user_input}/templates/${camera_gen}/META-INF/com/google/android/update-binary" ]; then
      candidate_path="${user_input}/templates/${camera_gen}"
    fi

    if [ -n "$candidate_path" ]; then
      TEMPLATES_DIR="$(cd "$candidate_path" && pwd)"
      log_ok "Using user-specified recovery templates from: $TEMPLATES_DIR"
      return 0
    else
      log_warn "Specified directory did not contain valid recovery templates for ${gen_name}."
      log_info "Proceeding with automatic download from GitHub..."
    fi
  fi

  # 5. Remote download from GitHub repository
  log_info "Downloading ${gen_name} recovery templates from GitHub repository..."
  local dest_base="./templates/${camera_gen}"
  if mkdir -p "$dest_base" 2>/dev/null && [ -w "$dest_base" ]; then
    TEMPLATES_DIR="$(cd "$dest_base" && pwd)"
  else
    TEMPLATES_DIR="${target_work_dir}/downloaded_templates/${camera_gen}"
    mkdir -p "$TEMPLATES_DIR"
  fi

  mkdir -p "${TEMPLATES_DIR}/META-INF/com/google/android" "${TEMPLATES_DIR}/addon.d"

  local files=(
    "templates/${camera_gen}/build.prop"
    "templates/${camera_gen}/toybox"
    "templates/${camera_gen}/addon.d/addond_head"
    "templates/${camera_gen}/addon.d/addond_tail"
    "templates/${camera_gen}/META-INF/com/google/android/update-binary"
    "templates/${camera_gen}/META-INF/com/google/android/updater-script"
  )

  for file in "${files[@]}"; do
    local rel_dest="${file#templates/${camera_gen}/}"
    local dest="${TEMPLATES_DIR}/${rel_dest}"
    mkdir -p "$(dirname "$dest")"
    local url="${GITHUB_RAW_BASE}/${file}"
    local fallback_url=""
    if [ "$camera_gen" = "camera4" ]; then
      fallback_url="https://raw.githubusercontent.com/vrwindsor1/Universal_MotCamera4Suite_Installer/main/templates/recovery/${rel_dest}"
    fi

    local dl_ok=0
    if command -v curl &>/dev/null; then
      if curl -sSfL "$url" -o "$dest" 2>/dev/null; then
        dl_ok=1
      elif [ -n "$fallback_url" ] && curl -sSfL "$fallback_url" -o "$dest" 2>/dev/null; then
        dl_ok=1
      fi
    elif command -v wget &>/dev/null; then
      if wget -q "$url" -O "$dest" 2>/dev/null; then
        dl_ok=1
      elif [ -n "$fallback_url" ] && wget -q "$fallback_url" -O "$dest" 2>/dev/null; then
        dl_ok=1
      fi
    else
      log_err "curl or wget is required to download recovery templates."
      exit 1
    fi

    if [ "$dl_ok" -eq 0 ]; then
      log_err "Failed to download template file: $url"
      echo ""
      echo -e "${C_YELLOW}[NOTE]${C_RESET} The recovery template module '${camera_gen}' (${gen_name}) is currently in development / not yet available."
      echo "Currently active & working module: Moto Camera 4 ('camera4')."
      echo "Support for ${gen_name} will be added in a future update."
      exit 1
    fi
  done

  chmod +x "${TEMPLATES_DIR}/toybox" "${TEMPLATES_DIR}/META-INF/com/google/android/update-binary" 2>/dev/null || true
  log_ok "Recovery templates for ${gen_name} successfully downloaded to: ${TEMPLATES_DIR}"
}

# ------------------------------------------------------------------------------
# 7. Dynamic Camera Properties Harvester
# ------------------------------------------------------------------------------
harvest_camera_properties() {
  local src_root="$1"
  local output_prop="$2"

  log_info "Harvesting device-specific multi-camera system properties..."
  rm -f "$output_prop"
  touch "$output_prop"

  cat <<EOF >> "$output_prop"
# ==============================================================================
# Auto-harvested Motorola Camera Properties
# Device: ${DEVICE_MODEL} (${DEVICE_CODENAME})
# Generation: ${CAMERA_GEN_NAME} (${CAMERA_VER})
# Firmware: ${BUILD_ID} (Android ${ANDROID_VERSION}, SDK ${SDK_LEVEL})
# ==============================================================================
ro.motocamera.device=${DEVICE_CODENAME}
ro.motocamera.model=${DEVICE_MODEL}
ro.motocamera.android=${ANDROID_VERSION}
ro.motocamera.sdk=${SDK_LEVEL}
ro.motocamera.build_id=${BUILD_ID}
ro.motocamera.version=${CAMERA_VER}
ro.motocamera.generation=${CAMERA_GEN}

EOF

  local harvested_keys=()

  for prop_file in "${PROP_FILES[@]}"; do
    if [ -f "$prop_file" ]; then
      while IFS='=' read -r key val || [ -n "$key" ]; do
        case "$key" in
          persist.vendor.camera.*|\
          vendor.camera.aux.*|\
          ro.vendor.camera.aux.*|\
          ro.camera.cfa.*|\
          camera.disable_zsl_mode|\
          ro.camera.enableCamera1MaxZsl)
            clean_key=$(echo "$key" | tr -d ' \r\t')
            clean_val=$(echo "$val" | tr -d '\r')
            if [ -n "$clean_key" ] && [[ ! " ${harvested_keys[*]} " =~ " ${clean_key} " ]]; then
              echo "${clean_key}=${clean_val}" >> "$output_prop"
              harvested_keys+=("$clean_key")
            fi
            ;;
        esac
      done < "$prop_file"
    fi
  done

  # Guarantee baseline aux camera unlock if not found
  if [[ ! " ${harvested_keys[*]} " =~ " persist.vendor.camera.expose.aux " ]]; then
    echo "persist.vendor.camera.expose.aux=1" >> "$output_prop"
  fi

  log_ok "Harvested ${#harvested_keys[@]} device camera properties."
}

# ------------------------------------------------------------------------------
# 8. Proprietary Component Harvester
# ------------------------------------------------------------------------------
harvest_blobs() {
  local src_root="$1"
  local staging_dir="$2"
  local camera_gen="$3"

  log_info "Harvesting ${CAMERA_GEN_NAME} binaries, libraries, and frameworks..."
  rm -rf "$staging_dir"
  mkdir -p "${staging_dir}/system"

  local sys_path="${src_root}/system"
  [ -d "${src_root}/system/system" ] && sys_path="${src_root}/system/system"

  # ----------------------------------------------------------------------------
  # 1. Product Partition Components
  # ----------------------------------------------------------------------------
  log_info "  - Harvesting Product applications & permissions..."
  mkdir -p "${staging_dir}/system/product/priv-app"
  mkdir -p "${staging_dir}/system/product/app"
  mkdir -p "${staging_dir}/system/product/etc/permissions"
  mkdir -p "${staging_dir}/system/product/etc/sysconfig"
  mkdir -p "${staging_dir}/system/product/etc/init"
  mkdir -p "${staging_dir}/system/product/etc/MotoDesktopAppConfig"

  # Main Camera app directory
  if [ -n "$CAMERA_MAIN_APK" ]; then
    local cam_parent_dir
    cam_parent_dir="$(dirname "$CAMERA_MAIN_APK")"
    local cam_folder_name="${cam_parent_dir##*/}"
    cp -rf "$cam_parent_dir" "${staging_dir}/system/product/priv-app/"
  fi

  # Companion AI Scene Engine
  local ai_src_dir
  ai_src_dir=$(find "${src_root}/product" -type d -name "MotCamera*AI*" 2>/dev/null | head -n1)
  if [ -n "$ai_src_dir" ]; then
    cp -rf "$ai_src_dir" "${staging_dir}/system/product/app/"
    log_ok "Harvested AI Scene Engine: ${ai_src_dir##*/}"
  fi

  # Permissions and sysconfigs
  cp -f "${src_root}/product/etc/permissions/"*com.motorola.camera* "${staging_dir}/system/product/etc/permissions/" 2>/dev/null || true
  cp -f "${src_root}/product/etc/sysconfig/"*com.motorola.camera* "${staging_dir}/system/product/etc/sysconfig/" 2>/dev/null || true
  cp -f "${src_root}/product/etc/init/"*motcamera* "${staging_dir}/system/product/etc/init/" 2>/dev/null || true
  [ -d "${src_root}/product/etc/MotoDesktopAppConfig" ] && cp -rf "${src_root}/product/etc/MotoDesktopAppConfig/"* "${staging_dir}/system/product/etc/MotoDesktopAppConfig/" 2>/dev/null || true

  # Shutter/focus sounds if present
  if [ -d "${src_root}/product/media/audio/ui" ]; then
    mkdir -p "${staging_dir}/system/product/media/audio/ui"
    cp -f "${src_root}/product/media/audio/ui/"camera_* "${staging_dir}/system/product/media/audio/ui/" 2>/dev/null || true
  fi

  # ----------------------------------------------------------------------------
  # 2. System_ext Partition Components
  # ----------------------------------------------------------------------------
  log_info "  - Harvesting System_ext ImagerTuning, Desktop, frameworks, and libs..."
  mkdir -p "${staging_dir}/system/system_ext/priv-app"
  mkdir -p "${staging_dir}/system/system_ext/framework"
  mkdir -p "${staging_dir}/system/system_ext/lib64"
  mkdir -p "${staging_dir}/system/system_ext/etc/permissions"
  mkdir -p "${staging_dir}/system/system_ext/etc/enable-disable-packages"
  mkdir -p "${staging_dir}/system/system_ext/etc/sysconfig"

  # Dynamic ImagerTuning app directory
  while IFS= read -r -d $'\0' d; do
    [ -n "$d" ] && cp -rf "$d" "${staging_dir}/system/system_ext/priv-app/"
  done < <(find "${src_root}/system_ext/priv-app" -maxdepth 1 -type d -name "ImagerTuning*" -print0 2>/dev/null)

  # MotCameraDesktop app directory
  if [ -d "${src_root}/system_ext/priv-app/MotCameraDesktop" ]; then
    cp -rf "${src_root}/system_ext/priv-app/MotCameraDesktop" "${staging_dir}/system/system_ext/priv-app/"
  fi

  # Frameworks and permissions
  cp -f "${src_root}/system_ext/framework/"*com.motorola.* "${staging_dir}/system/system_ext/framework/" 2>/dev/null || true
  cp -f "${src_root}/system_ext/etc/permissions/"*motorola* "${staging_dir}/system/system_ext/etc/permissions/" 2>/dev/null || true
  cp -f "${src_root}/system_ext/etc/permissions/"*imager* "${staging_dir}/system/system_ext/etc/permissions/" 2>/dev/null || true
  cp -f "${src_root}/system_ext/etc/permissions/"*camera* "${staging_dir}/system/system_ext/etc/permissions/" 2>/dev/null || true
  cp -f "${src_root}/system_ext/etc/public.libraries-"* "${staging_dir}/system/system_ext/etc/" 2>/dev/null || true
  cp -f "${src_root}/system_ext/etc/enable-disable-packages/"*camera* "${staging_dir}/system/system_ext/etc/enable-disable-packages/" 2>/dev/null || true
  cp -f "${src_root}/system_ext/etc/enable-disable-packages/"*desktop* "${staging_dir}/system/system_ext/etc/enable-disable-packages/" 2>/dev/null || true
  cp -f "${src_root}/system_ext/etc/sysconfig/"* "${staging_dir}/system/system_ext/etc/sysconfig/" 2>/dev/null || true

  # System_ext native libraries
  for lib_arch in lib64 lib; do
    local src_lib_dir="${src_root}/system_ext/${lib_arch}"
    if [ -d "$src_lib_dir" ]; then
      local dst_lib_dir="${staging_dir}/system/system_ext/${lib_arch}"
      mkdir -p "$dst_lib_dir"
      for pattern in "libarcsoft*" "libcamera*" "libimgTuner*" "libjni_helper*" "libopencv*" "motorola.hardware.camera*"; do
        while IFS= read -r -d $'\0' lib_file; do
          [ -n "$lib_file" ] && cp -f "$lib_file" "$dst_lib_dir/"
        done < <(find "$src_lib_dir" -maxdepth 1 -type f -name "$pattern" -print0 2>/dev/null)
      done
    fi
  done

  # ----------------------------------------------------------------------------
  # 3. System Framework and Signature Libraries
  # ----------------------------------------------------------------------------
  log_info "  - Harvesting System framework signature libraries..."
  mkdir -p "${staging_dir}/system/framework"
  mkdir -p "${staging_dir}/system/etc/permissions"
  mkdir -p "${staging_dir}/system/lib64"

  cp -f "${sys_path}/framework/com.motorola.motosignature.jar" "${staging_dir}/system/framework/" 2>/dev/null || true
  cp -f "${sys_path}/framework/moto-core_services.jar" "${staging_dir}/system/framework/" 2>/dev/null || true
  cp -f "${sys_path}/framework/moto-settings.jar" "${staging_dir}/system/framework/" 2>/dev/null || true
  cp -f "${sys_path}/etc/permissions/com.motorola.motosignature.xml" "${staging_dir}/system/etc/permissions/" 2>/dev/null || true
  cp -f "${sys_path}/etc/permissions/moto-core_services.xml" "${staging_dir}/system/etc/permissions/" 2>/dev/null || true
  cp -f "${sys_path}/etc/permissions/moto-settings.xml" "${staging_dir}/system/etc/permissions/" 2>/dev/null || true

  for lib_arch in lib64 lib; do
    if [ -d "${sys_path}/${lib_arch}" ]; then
      mkdir -p "${staging_dir}/system/${lib_arch}"
      while IFS= read -r -d $'\0' lib_file; do
        [ -n "$lib_file" ] && cp -f "$lib_file" "${staging_dir}/system/${lib_arch}/"
      done < <(find "${sys_path}/${lib_arch}" -maxdepth 1 -type f -name "motorola.hardware.camera*" -print0 2>/dev/null)
    fi
  done

  # ----------------------------------------------------------------------------
  # 4. Vendor Camera HAL & VINTF Manifest
  # ----------------------------------------------------------------------------
  log_info "  - Harvesting Vendor HAL services and VINTF manifests..."
  mkdir -p "${staging_dir}/system/vendor/bin/hw"
  mkdir -p "${staging_dir}/system/vendor/etc/init"
  mkdir -p "${staging_dir}/system/vendor/etc/vintf/manifest"
  mkdir -p "${staging_dir}/system/vendor/lib64/hw"

  # Hardware Daemons
  while IFS= read -r -d $'\0' bin_file; do
    [ -n "$bin_file" ] && cp -f "$bin_file" "${staging_dir}/system/vendor/bin/hw/"
  done < <(find "${src_root}/vendor/bin/hw" -maxdepth 1 -type f -name "motorola.hardware.camera.*" -print0 2>/dev/null)

  # Init rc files
  while IFS= read -r -d $'\0' rc_file; do
    [ -n "$rc_file" ] && cp -f "$rc_file" "${staging_dir}/system/vendor/etc/init/"
  done < <(find "${src_root}/vendor/etc/init" -maxdepth 1 -type f -name "motorola.hardware.camera.*" -print0 2>/dev/null)

  # Vendor HAL libraries
  for lib_arch in lib64 lib; do
    if [ -d "${src_root}/vendor/${lib_arch}" ]; then
      mkdir -p "${staging_dir}/system/vendor/${lib_arch}/hw"
      while IFS= read -r -d $'\0' lib_file; do
        [ -n "$lib_file" ] && cp -f "$lib_file" "${staging_dir}/system/vendor/${lib_arch}/hw/"
      done < <(find "${src_root}/vendor/${lib_arch}/hw" -maxdepth 1 -type f -name "motorola.hardware.camera.*" -print0 2>/dev/null)

      while IFS= read -r -d $'\0' lib_file; do
        [ -n "$lib_file" ] && cp -f "$lib_file" "${staging_dir}/system/vendor/${lib_arch}/"
      done < <(find "${src_root}/vendor/${lib_arch}" -maxdepth 1 -type f \( -name "motorola.hardware.camera.*" -o -name "libmot_chi_desktop_helper*" \) -print0 2>/dev/null)
    fi
  done

  # VINTF Manifest
  local vintf_file="${staging_dir}/system/vendor/etc/vintf/manifest/manifest_imgtuner.xml"
  if [ -f "${src_root}/vendor/etc/vintf/manifest/manifest_imgtuner.xml" ]; then
    cp -f "${src_root}/vendor/etc/vintf/manifest/manifest_imgtuner.xml" "$vintf_file"
  else
    cat <<'EOF' > "$vintf_file"
<manifest version="1.0" type="device">
    <hal format="hidl">
        <name>motorola.hardware.camera.imgtuner</name>
        <transport>hwbinder</transport>
        <version>1.0</version>
        <version>2.0</version>
        <interface>
            <name>IImageTuning</name>
            <instance>default</instance>
        </interface>
        <fqname>@1.0::IImageTuning/default</fqname>
        <fqname>@2.0::IImageTuning/default</fqname>
    </hal>
</manifest>
EOF
  fi

  log_ok "All ${CAMERA_GEN_NAME} proprietary blobs harvested successfully."
}

# ------------------------------------------------------------------------------
# 9. Recovery Package Assembly
# ------------------------------------------------------------------------------
build_recovery_package() {
  local staging_dir="$1"
  local output_dir="$2"
  local build_tmp="$3"
  local camera_prop="$4"

  mkdir -p "$output_dir"
  local abs_output_dir="$(cd "$output_dir" && pwd)"

  log_info "Assembling flashable recovery installer for ${DEVICE_MODEL} (${DEVICE_CODENAME})..."
  local rec_build="${build_tmp}/recovery_build"
  rm -rf "$rec_build"
  mkdir -p "$rec_build"

  # Copy recovery scaffolding templates
  cp -rf "${TEMPLATES_DIR}/"* "$rec_build/"

  # Update template build.prop with detected firmware version
  cat <<EOF > "${rec_build}/build.prop"
arch=arm64
version=${SDK_LEVEL}
version_nice=${ANDROID_VERSION}.0.0
ro.product.device=${DEVICE_CODENAME}
ro.product.model=${DEVICE_MODEL}
EOF

  # Ensure addon.d scripts are placed inside system/addon.d
  mkdir -p "${rec_build}/system/addon.d"
  cp -rf "${TEMPLATES_DIR}/addon.d/"* "${rec_build}/system/addon.d/"
  rm -rf "${rec_build}/addon.d"

  # Copy harvested camera components
  cp -rf "${staging_dir}/system/"* "${rec_build}/system/"

  # Embed device properties file inside package root
  cp -f "$camera_prop" "${rec_build}/motocamera.prop"

  # Package flashable recovery ZIP
  local rec_zip="${abs_output_dir}/MotoCameraRestored_${DEVICE_CODENAME}_Recovery_Installer.zip"
  rm -f "$rec_zip"
  (cd "$rec_build" && zip -r9q "$rec_zip" .)

  # Write metadata summary text
  local info_file="${abs_output_dir}/MotoCameraRestored_${DEVICE_CODENAME}_info.txt"
  cat <<EOF > "$info_file"
================================================================================
Moto Camera Restored — Recovery Package Build Manifest
================================================================================
Device Model:       ${DEVICE_MODEL}
Device Codename:    ${DEVICE_CODENAME}
Hardware Platform:  ${PLATFORM_SOC}
Android Version:    ${ANDROID_VERSION} (API SDK ${SDK_LEVEL})
Stock Build ID:     ${BUILD_ID}
Camera Generation:  ${CAMERA_GEN_NAME} (${CAMERA_VER})
Template Module:    ${CAMERA_GEN}
Installer ZIP:      ${rec_zip##*/}
Build Timestamp:    $(date -u +"%Y-%m-%d %H:%M:%S UTC")
================================================================================
EOF

  log_ok "Recovery Installer created: $rec_zip ($(du -h "$rec_zip" | cut -f1))"
  log_ok "Build manifest saved: $info_file"
}

# ------------------------------------------------------------------------------
# Cleanup handler
# ------------------------------------------------------------------------------
cleanup() {
  if [ ${#MOUNTED_DIRS[@]} -gt 0 ]; then
    log_info "Unmounting loop mounts..."
    for mnt in "${MOUNTED_DIRS[@]}"; do
      umount -l "$mnt" 2>/dev/null || true
    done
  fi

  if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR" 2>/dev/null || true
  fi
}

trap cleanup EXIT INT TERM

# ------------------------------------------------------------------------------
# Main Execution
# ------------------------------------------------------------------------------
main() {
  banner
  setup_environment
  check_dependencies

  local cli_input="$1"
  local cli_out="$2"
  local cli_template="$3"

  local out_dir="${cli_out:-$DEFAULT_OUTPUT_DIR}"
  mkdir -p "$out_dir"
  local abs_out_dir="$(cd "$out_dir" && pwd)"

  local base_work_dir="${abs_out_dir}/.build_tmp"
  mkdir -p "$base_work_dir"
  WORK_DIR="$(mktemp -d "${base_work_dir}/motocamera_build_XXXXXX" 2>/dev/null || mktemp -d /tmp/motocamera_build_XXXXXX)"

  log_info "Working directory initialized: $WORK_DIR"

  get_firmware_path "$cli_input"
  extract_firmware "$FIRMWARE_INPUT" "$WORK_DIR"

  profile_device "$FIRMWARE_ROOT"
  detect_camera_generation "$FIRMWARE_ROOT"

  ensure_templates "$WORK_DIR" "$CAMERA_GEN" "$CAMERA_GEN_NAME" "$cli_template"

  local camera_prop="${WORK_DIR}/motocamera.prop"
  harvest_camera_properties "$FIRMWARE_ROOT" "$camera_prop"

  local staging_dir="${WORK_DIR}/staging"
  harvest_blobs "$FIRMWARE_ROOT" "$staging_dir" "$CAMERA_GEN"

  build_recovery_package "$staging_dir" "$abs_out_dir" "$WORK_DIR" "$camera_prop"

  local rec_zip="${abs_out_dir}/MotoCameraRestored_${DEVICE_CODENAME}_Recovery_Installer.zip"
  echo ""
  echo -e "${C_BOLD}${C_GREEN}================================================================================"
  echo "          Universal Recovery Package Compiled Successfully!                     "
  echo -e "================================================================================${C_RESET}"
  echo ""
  echo "Target Device:"
  echo "  --> Model:      ${DEVICE_MODEL}"
  echo "  --> Codename:   ${DEVICE_CODENAME}"
  echo "  --> Generation: ${CAMERA_GEN_NAME} (${CAMERA_VER})"
  echo "  --> Module:     templates/${CAMERA_GEN}"
  echo ""
  echo "Installer Package:"
  echo "  --> ${rec_zip}"
  echo ""
  echo "How to install via Lineage Recovery / TWRP / OrangeFox:"
  echo "  1. Reboot your phone into Recovery mode."
  echo "  2. Select 'Apply Update' -> 'Apply from ADB' (or 'Install' in TWRP/OrangeFox)."
  echo "  3. From your PC terminal, run:"
  echo "       adb sideload \"${rec_zip}\""
  echo "  4. If prompted with 'Signature verification failed. Install anyway?', select 'Yes'."
  echo "  5. Reboot system. Native ${CAMERA_GEN_NAME} is restored and ready to use!"
  echo ""
  echo -e "${C_CYAN}[OTA Survival]${C_RESET} The included addon.d script will automatically"
  echo "preserve the camera suite across nightly custom ROM updates."
  echo ""
}

main "$@"
