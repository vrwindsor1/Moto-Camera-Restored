#!/usr/bin/env bash
# ==============================================================================
# Moto Camera Restored — Universal Recovery Package Compiler [DEBUG EDITION]
# Modular Multi-Generation Motorola Camera Restoration & Diagnostics Toolkit
#
# Debug Edition Features:
#   * Embeds diagnostic update-binary (TEMPLATE_SCHEMA_VERSION=2_DEBUG) that audits:
#       - Previous-boot /sys/fs/pstore ramoops crash & bootloop logs
#       - Read-only /vendor VINTF SELinux context health & legacy flash residue
#       - /system_ext public.libraries-*.txt Zygote libnativeloader integrity
#       - Partition mount rw probes, df free space/inodes, and ROM build.prop
#       - Full post-copy ls -laZ SELinux context verification & kernel dmesg
#   * Exports the install debug log on-device to:
#       - <ZipName>.debug.log (automatically next to the .zip on SD / USB-OTG)
#       - /tmp/motocamera_debug.log (Recovery RAM disk)
#       - /system_ext/etc/motocamera_install_debug.log (persists across reboots)
#   * Generates a companion Linux ADB Sideload + Auto-Log-Pull wrapper script
#     (.sh) that sideloads the .zip and saves <ZipName>.debug.log right next to
#     the .zip on the Linux host!
#
# Generates:
#   MotoCameraRestored_<Codename>_<BuildVersion>_DEBUG_Recovery_Installer.zip
#   MotoCameraRestored_<Codename>_<BuildVersion>_DEBUG_Recovery_Installer.txt
#   MotoCameraRestored_<Codename>_<BuildVersion>_DEBUG_ADB_Install.sh
#
# Usage:
#   Interactive:  ./compile_recovery_package_linux_debug.sh
#   CLI:          ./compile_recovery_package_linux_debug.sh "/path/to/stock_firmware" [output_dir] [template_dir]
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
  echo -e "${C_BOLD}${C_YELLOW}"
  echo "================================================================================"
  echo "       Moto Camera Restored — Recovery Package Compiler [DEBUG EDITION]         "
  echo "       Diagnostic Logging, Health Audit & Remote Troubleshooting Builder        "
  echo "================================================================================"
  echo -e "${C_PURPLE}               ⚡ Pair Programmed with Google DeepMind Antigravity               ${C_RESET}"
  echo -e "${C_BOLD}${C_YELLOW}================================================================================${C_RESET}"
  echo ""
}

# ------------------------------------------------------------------------------
# 0. Environment Setup (Ensure tools in PATH even under sudo)
# ------------------------------------------------------------------------------
setup_environment() {
  if [ -n "$SUDO_USER" ]; then
    local real_home
    real_home=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6 || true)
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

  # Verify EXT4 extraction capability (Android 10-13 & hybrid partitions):
  local ext4_capable=0
  if command -v debugfs &>/dev/null; then
    ext4_capable=1
  elif command -v 7zz &>/dev/null || command -v 7z &>/dev/null || command -v 7za &>/dev/null; then
    ext4_capable=1
  elif [ "$(id -u)" -eq 0 ]; then
    ext4_capable=1
  fi

  if [ "$ext4_capable" -eq 0 ]; then
    missing+=("e2fsprogs (debugfs)")
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    log_err "Missing required build tools: ${missing[*]}"
    echo ""
    echo "Please install dependencies for your distribution:"
    echo "  Fedora / RHEL:   sudo dnf install android-tools erofs-utils e2fsprogs zip curl python3"
    echo "  Ubuntu / Debian: sudo apt install android-sdk-libsparse-utils erofs-utils e2fsprogs zip curl python3"
    echo "  Arch Linux:      sudo pacman -S android-tools erofs-utils e2fsprogs zip curl python"
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
    [ -d "${work_dir}/unpacked_zip" ] && rm -rf "${work_dir}/unpacked_zip"
    log_ok "Unpacking dynamic partitions from super.raw.img with lpunpack..."
    lpunpack "${work_dir}/super.raw.img" "$partitions_dir"
    rm -f "${work_dir}/super.raw.img"
  elif [ -f "${src}/super.img" ] || [ -f "${src}/super.raw.img" ]; then
    local super_img="${src}/super.img"
    [ ! -f "$super_img" ] && super_img="${src}/super.raw.img"
    log_info "Found super partition image: $super_img"
    local super_magic
    super_magic=$(od -An -tx4 -N 4 "$super_img" 2>/dev/null | tr -d ' \n' || true)
    if [ "$super_magic" = "ed26ff3a" ]; then
      log_info "Converting sparse super.img to raw image..."
      simg2img "$super_img" "${work_dir}/super.raw.img"
      [ -d "${work_dir}/unpacked_zip" ] && rm -rf "${work_dir}/unpacked_zip"
      lpunpack "${work_dir}/super.raw.img" "$partitions_dir"
      rm -f "${work_dir}/super.raw.img"
    else
      lpunpack "$super_img" "$partitions_dir"
      [ -d "${work_dir}/unpacked_zip" ] && rm -rf "${work_dir}/unpacked_zip"
    fi
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
      [ -d "${work_dir}/unpacked_zip" ] && rm -rf "${work_dir}/unpacked_zip"
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
      if [ -s "$candidate" ]; then
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

    # Automatically unsparse standalone sparse partition images if needed
    local img_sparse_magic
    img_sparse_magic=$(od -An -tx4 -N 4 "$img" 2>/dev/null | tr -d ' \n' || true)
    if [ "$img_sparse_magic" = "ed26ff3a" ]; then
      log_info "Converting sparse ${part} image (${img##*/}) to raw..."
      simg2img "$img" "${work_dir}/${part}.raw.img"
      img="${work_dir}/${part}.raw.img"
    fi

    # Detect filesystem superblock magic (EROFS: 0xe0f5e1e2 @ 1024, EXT4: 0xef53 @ 1080)
    local fs_type="unknown"
    local erofs_magic ext4_magic
    erofs_magic=$(od -An -tx4 -j 1024 -N 4 "$img" 2>/dev/null | tr -d ' \n' || true)
    ext4_magic=$(od -An -tx2 -j 1080 -N 2 "$img" 2>/dev/null | tr -d ' \n' || true)
    if [ "$erofs_magic" = "e0f5e1e2" ]; then
      fs_type="erofs"
    elif [ "$ext4_magic" = "ef53" ]; then
      fs_type="ext4"
    fi

    local target_part_dir="${extracted_dir}/${part}"
    mkdir -p "$target_part_dir"

    log_info "Extracting ${part} partition (${img##*/}, ${fs_type})..."
    local extracted=0
    local mounted=0

    # Strategy 1: Loop mount if root
    if [ "$(id -u)" -eq 0 ]; then
      if mount -t erofs -o loop,ro "$img" "$target_part_dir" 2>/dev/null || mount -t ext4 -o loop,ro "$img" "$target_part_dir" 2>/dev/null; then
        MOUNTED_DIRS+=("$target_part_dir")
        extracted=1
        mounted=1
        log_ok "Mounted ${part} partition via kernel loop."
      fi
    fi

    # Strategy 2: EROFS user-space extraction (erofs-extract or fsck.erofs)
    if [ "$extracted" -eq 0 ] && [ "$fs_type" != "ext4" ]; then
      if command -v erofs-extract &>/dev/null; then
        erofs-extract --extract="$target_part_dir" --overwrite "$img" 2>/dev/null || true
      elif command -v fsck.erofs &>/dev/null; then
        fsck.erofs --extract="$target_part_dir" --overwrite "$img" 2>/dev/null || true
      fi

      if [ -n "$(find "$target_part_dir" -mindepth 1 -maxdepth 1 2>/dev/null | head -n1 || true)" ]; then
        chmod -R u+rwX "$target_part_dir" 2>/dev/null || true
        extracted=1
      fi
    fi

    # Strategy 3: EXT4 user-space extraction (debugfs rdump or 7z/7zz/7za)
    if [ "$extracted" -eq 0 ] && [ "$fs_type" != "erofs" ]; then
      if command -v debugfs &>/dev/null; then
        debugfs -R "rdump / \"${target_part_dir}\"" "$img" >/dev/null 2>&1 || true
        chmod -R u+rwX "$target_part_dir" 2>/dev/null || true
        if [ -n "$(find "$target_part_dir" -mindepth 1 -maxdepth 1 ! -name 'lost+found' 2>/dev/null | head -n1 || true)" ]; then
          extracted=1
        fi
      fi

      if [ "$extracted" -eq 0 ]; then
        for sevenz in 7zz 7z 7za; do
          if command -v "$sevenz" &>/dev/null; then
            "$sevenz" x -y "$img" -o"$target_part_dir" >/dev/null 2>&1 || true
            chmod -R u+rwX "$target_part_dir" 2>/dev/null || true
            if [ -n "$(find "$target_part_dir" -mindepth 1 -maxdepth 1 ! -name 'lost+found' 2>/dev/null | head -n1 || true)" ]; then
              extracted=1
              break
            fi
          fi
        done
      fi
    fi

    # Free unpacked temporary image once extracted to keep disk footprint low
    if [ "$mounted" -eq 0 ]; then
      if [ "$partitions_dir" = "${work_dir}/partitions" ] && [ -f "$img" ]; then
        rm -f "$img" 2>/dev/null || true
      elif [ "$img" = "${work_dir}/${part}.raw.img" ]; then
        rm -f "$img" 2>/dev/null || true
      fi
    fi

    if [ "$extracted" -eq 0 ]; then
      if [ "$part" = "odm" ]; then
        log_warn "Optional odm partition (${img##*/}) had no extractable files; skipping."
        continue
      fi
      log_err "Failed to extract ${part} partition (${img##*/}, detected format: ${fs_type})!"
      log_err "Please verify erofs-utils and e2fsprogs (debugfs) are installed:"
      log_err "  Fedora: sudo dnf install erofs-utils e2fsprogs | Ubuntu: sudo apt install erofs-utils e2fsprogs"
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
      val=$(grep -E "^${key}=" "$file" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '\r' || true)
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
    cam_perm=$(find "${src_root}/product/etc/permissions" -name "com.motorola.camera*.*.xml" 2>/dev/null | head -n1 || true)
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

  BUILD_DISPLAY_ID=$(read_prop "ro.build.display.id" "${PROP_FILES[@]}" || \
                     read_prop "ro.mot.build.version.release" "${PROP_FILES[@]}" || \
                     read_prop "ro.build.version.full" "${PROP_FILES[@]}" || echo "")

  BUILD_ID=$(read_prop "ro.build.id" "${PROP_FILES[@]}" || \
             read_prop "ro.product.build.id" "${PROP_FILES[@]}" || \
             read_prop "ro.system.build.id" "${PROP_FILES[@]}" || echo "")

  ROM_BUILD_VERSION="${BUILD_DISPLAY_ID:-$BUILD_ID}"
  [ -z "$ROM_BUILD_VERSION" ] && ROM_BUILD_VERSION="UNKNOWN"
  [ -z "$BUILD_ID" ] && BUILD_ID="$ROM_BUILD_VERSION"

  PLATFORM_SOC=$(read_prop "ro.board.platform" "${PROP_FILES[@]}" || \
                 read_prop "ro.hardware" "${PROP_FILES[@]}" || \
                 read_prop "ro.product.board" "${PROP_FILES[@]}" || echo "unknown")

  log_profile "Detected Stock Firmware Profile:"
  echo -e "    ${C_BOLD}Model:${C_RESET}         ${DEVICE_MODEL}"
  echo -e "    ${C_BOLD}Codename:${C_RESET}      ${DEVICE_CODENAME}"
  echo -e "    ${C_BOLD}Platform:${C_RESET}      ${PLATFORM_SOC}"
  echo -e "    ${C_BOLD}Android:${C_RESET}       ${ANDROID_VERSION} (API SDK ${SDK_LEVEL})"
  echo -e "    ${C_BOLD}Build Version:${C_RESET} ${ROM_BUILD_VERSION}"
  if [ "$ROM_BUILD_VERSION" != "$BUILD_ID" ] && [ -n "$BUILD_ID" ]; then
    echo -e "    ${C_BOLD}Build ID:${C_RESET}      ${BUILD_ID}"
  fi
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
  cam5_apk=$(find "$src_root" -type f \( -name "MotCamera5.apk" -o -name "*camera5*.apk" \) 2>/dev/null | head -n1 || true)
  if [ -n "$cam5_apk" ]; then
    CAMERA_GEN="camera5"
    CAMERA_GEN_NAME="Moto Camera 5"
    CAMERA_MAIN_APK="$cam5_apk"
    CAMERA_VER="v10.x"
  fi

  # 2. Check for Moto Camera 4 (MotCamera4.apk or MotCamera3 with version 9.x)
  if [ -z "$CAMERA_GEN" ]; then
    local cam4_apk
    cam4_apk=$(find "$src_root" -type f -name "MotCamera4.apk" 2>/dev/null | head -n1 || true)
    if [ -n "$cam4_apk" ]; then
      CAMERA_GEN="camera4"
      CAMERA_GEN_NAME="Moto Camera 4"
      CAMERA_MAIN_APK="$cam4_apk"
    fi
  fi

  # 3. Check for Moto Camera 3 (MotCamera3.apk / com.motorola.camera3)
  if [ -z "$CAMERA_GEN" ]; then
    local cam3_apk
    cam3_apk=$(find "$src_root" -type f \( -name "MotCamera3.apk" -o -name "MotCamera.apk" \) 2>/dev/null | head -n1 || true)
    if [ -n "$cam3_apk" ]; then
      # Distinguish Camera 4 (v9.x) vs Camera 3 (v8.x/v7.x)
      local ver_check=""
      if command -v python3 &>/dev/null; then
        ver_check=$(python3 -c '
import zipfile, re, sys
try:
    with zipfile.ZipFile(sys.argv[1], "r") as z:
        for name in ["classes.dex", "classes2.dex"]:
            if name in z.namelist():
                m = re.findall(rb"9\.[0-9]+\.[0-9]+\.[0-9]+", z.read(name))
                if m:
                    print("camera4")
                    sys.exit(0)
except Exception:
    pass
print("camera3")
' "$cam3_apk" 2>/dev/null || true)
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
    cam2_apk=$(find "$src_root" -type f \( -name "MotCamera2.apk" -o -name "*camera2*.apk" \) 2>/dev/null | head -n1 || true)
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
    CAMERA_VER=$(python3 -c '
import zipfile, re, struct, sys

def axml_ver(data):
    if len(data) < 8: return None
    ft, fhs, fs = struct.unpack_from("<HHI", data, 0)
    if ft != 0x0003: return None
    pos, strings, res_ids = fhs, [], []
    while pos + 8 <= len(data):
        ct, chs, cs = struct.unpack_from("<HHI", data, pos)
        if cs < 8 or pos + cs > len(data): break
        if ct == 0x0001 and cs >= 28:
            sc, _, flags, s_start, _ = struct.unpack_from("<IIIII", data, pos + 8)
            utf8 = (flags & (1 << 8)) != 0
            ob, sb = pos + chs, pos + s_start
            for i in range(sc):
                if ob + (i + 1) * 4 > pos + cs: break
                idx = sb + struct.unpack_from("<I", data, ob + i * 4)[0]
                try:
                    if utf8:
                        l1 = data[idx]; idx += 2 if (l1 & 0x80) else 1
                        l2 = data[idx]; idx += 1
                        if l2 & 0x80: l2 = ((l2 & 0x7f) << 8) | data[idx]; idx += 1
                        strings.append(data[idx:idx + l2].decode("utf-8", errors="ignore"))
                    else:
                        l1 = struct.unpack_from("<H", data, idx)[0]; idx += 2
                        if l1 & 0x8000: l1 = ((l1 & 0x7fff) << 16) | struct.unpack_from("<H", data, idx)[0]; idx += 2
                        strings.append(data[idx:idx + l1 * 2].decode("utf-16le", errors="ignore"))
                except Exception:
                    strings.append("")
        elif ct == 0x0180:
            cnt = (cs - chs) // 4
            res_ids = list(struct.unpack_from(f"<{cnt}I", data, pos + chs))
        elif ct == 0x0102 and pos + chs + 20 <= len(data):
            _, n_idx, a_start, a_size, a_cnt = struct.unpack_from("<IIHHH", data, pos + chs)
            if n_idx < len(strings) and strings[n_idx] == "manifest":
                ab = pos + chs + a_start
                for i in range(a_cnt):
                    ap = ab + i * a_size
                    if ap + 20 > pos + cs: break
                    _, an, araw, _, _, adt, adata = struct.unpack_from("<IIIHBBI", data, ap)
                    if (an < len(res_ids) and res_ids[an] == 0x0101021c) or (an < len(strings) and strings[an] == "versionName"):
                        if araw != 0xFFFFFFFF and araw < len(strings) and strings[araw]: return strings[araw].strip()
                        if adt == 0x03 and adata < len(strings) and strings[adata]: return strings[adata].strip()
                break
        pos += cs
    return None

try:
    with zipfile.ZipFile(sys.argv[1], "r") as z:
        if "AndroidManifest.xml" in z.namelist():
            v = axml_ver(z.read("AndroidManifest.xml"))
            if v:
                print(v)
                sys.exit(0)
        for name in ["classes.dex", "classes2.dex"]:
            if name in z.namelist():
                m = re.findall(rb"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+", z.read(name))
                if m:
                    print(m[0].decode())
                    sys.exit(0)
except Exception:
    pass
' "$CAMERA_MAIN_APK" 2>/dev/null || true)
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

  local required_schema="TEMPLATE_SCHEMA_VERSION=2"
  local local_dir="${SCRIPT_DIR}/templates/${camera_gen}"
  local cwd_dir="$(pwd)/templates/${camera_gen}"
  local refresh_stale=0
  local stale_target_dir=""

  # 2. Check local script directory path
  if [ -d "$local_dir" ] && [ -f "${local_dir}/META-INF/com/google/android/update-binary" ]; then
    if grep -q "$required_schema" "${local_dir}/META-INF/com/google/android/update-binary" 2>/dev/null; then
      TEMPLATES_DIR="$local_dir"
      log_ok "Found local recovery templates for ${gen_name} (${camera_gen})."
      return 0
    else
      log_warn "Outdated recovery template detected in '${local_dir}'; refreshing latest templates from GitHub..."
      refresh_stale=1
      stale_target_dir="$local_dir"
    fi
  fi

  # 3. Check current working directory path (if distinct from script directory)
  if [ "$cwd_dir" != "$local_dir" ] && [ -d "$cwd_dir" ] && [ -f "${cwd_dir}/META-INF/com/google/android/update-binary" ]; then
    if grep -q "$required_schema" "${cwd_dir}/META-INF/com/google/android/update-binary" 2>/dev/null; then
      TEMPLATES_DIR="$cwd_dir"
      log_ok "Found local recovery templates for ${gen_name} (${camera_gen})."
      return 0
    else
      log_warn "Outdated recovery template detected in '${cwd_dir}'; refreshing latest templates from GitHub..."
      refresh_stale=1
      stale_target_dir="$cwd_dir"
    fi
  fi

  # 4. Template folder not present in working directory -> Prompt the user (unless auto-refreshing stale cache)
  if [ "$refresh_stale" -eq 0 ]; then
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
  fi

  # 5. Remote download from GitHub repository
  log_info "Downloading ${gen_name} recovery templates from GitHub repository..."
  local dest_base="${stale_target_dir:-./templates/${camera_gen}}"
  if mkdir -p "${dest_base}/META-INF/com/google/android" "${dest_base}/addon.d" 2>/dev/null && \
     touch "${dest_base}/.write_probe" 2>/dev/null; then
    rm -f "${dest_base}/.write_probe" 2>/dev/null || true
    TEMPLATES_DIR="$(cd "$dest_base" && pwd)"
  else
    TEMPLATES_DIR="${target_work_dir}/downloaded_templates/${camera_gen}"
    mkdir -p "${TEMPLATES_DIR}/META-INF/com/google/android" "${TEMPLATES_DIR}/addon.d"
  fi

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

    local dl_ok=0
    if command -v curl &>/dev/null; then
      if curl -sSfL "$url" -o "$dest" 2>/dev/null; then
        dl_ok=1
      fi
    elif command -v wget &>/dev/null; then
      if wget -q "$url" -O "$dest" 2>/dev/null; then
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

ensure_debug_update_binary() {
  local target_work_dir="$1"
  local camera_gen="$2"
  local gen_name="$3"
  local cli_template="$4"

  local required_debug_schema="TEMPLATE_SCHEMA_VERSION=2_DEBUG"
  local rel_ub="META-INF/com/google/android/update-binary"

  # 1. Check CLI path if explicitly pointing to a debug template
  if [ -n "$cli_template" ]; then
    for cand in \
      "${cli_template}/${rel_ub}" \
      "${cli_template}/${camera_gen}_debug/${rel_ub}" \
      "${cli_template}/templates/${camera_gen}_debug/${rel_ub}"; do
      if [ -f "$cand" ] && grep -q "$required_debug_schema" "$cand" 2>/dev/null; then
        DEBUG_UPDATE_BINARY="$(cd "$(dirname "$cand")" && pwd)/update-binary"
        log_ok "Using CLI-specified diagnostic debug update-binary: $DEBUG_UPDATE_BINARY"
        return 0
      fi
    done
  fi

  local local_dbg="${SCRIPT_DIR}/templates/${camera_gen}_debug/${rel_ub}"
  local cwd_dbg="$(pwd)/templates/${camera_gen}_debug/${rel_ub}"

  # 2. Check script directory
  if [ -f "$local_dbg" ] && grep -q "$required_debug_schema" "$local_dbg" 2>/dev/null; then
    DEBUG_UPDATE_BINARY="$local_dbg"
    log_ok "Found local diagnostic debug update-binary (${camera_gen}_debug)."
    return 0
  fi

  # 3. Check current working directory
  if [ "$cwd_dbg" != "$local_dbg" ] && [ -f "$cwd_dbg" ] && grep -q "$required_debug_schema" "$cwd_dbg" 2>/dev/null; then
    DEBUG_UPDATE_BINARY="$cwd_dbg"
    log_ok "Found local diagnostic debug update-binary (${camera_gen}_debug)."
    return 0
  fi

  # 4. Remote download from GitHub repository
  log_info "Downloading diagnostic debug update-binary (${camera_gen}_debug) from GitHub..."
  local dest_base="./templates/${camera_gen}_debug"
  local dest_ub=""
  if mkdir -p "${dest_base}/META-INF/com/google/android" 2>/dev/null && \
     touch "${dest_base}/.write_probe" 2>/dev/null; then
    rm -f "${dest_base}/.write_probe" 2>/dev/null || true
    dest_ub="$(cd "$dest_base" && pwd)/${rel_ub}"
  else
    dest_ub="${target_work_dir}/downloaded_templates/${camera_gen}_debug/${rel_ub}"
    mkdir -p "$(dirname "$dest_ub")"
  fi

  local url="${GITHUB_RAW_BASE}/templates/${camera_gen}_debug/${rel_ub}"
  local dl_ok=0
  if command -v curl &>/dev/null; then
    curl -sSfL "$url" -o "$dest_ub" 2>/dev/null && dl_ok=1
  elif command -v wget &>/dev/null; then
    wget -q "$url" -O "$dest_ub" 2>/dev/null && dl_ok=1
  else
    log_err "curl or wget is required to download diagnostic debug template."
    exit 1
  fi

  if [ "$dl_ok" -eq 0 ] || [ ! -s "$dest_ub" ]; then
    log_err "Failed to download diagnostic debug template: $url"
    exit 1
  fi

  chmod +x "$dest_ub" 2>/dev/null || true
  DEBUG_UPDATE_BINARY="$dest_ub"
  log_ok "Diagnostic debug update-binary downloaded to: $DEBUG_UPDATE_BINARY"
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
strip_redundant_oat_if_dex_present() {
  local app_dir="$1"
  [ -d "$app_dir" ] || return 0

  while IFS= read -r -d $'\0' apk_file; do
    [ -f "$apk_file" ] || continue
    local has_dex=0
    if command -v python3 &>/dev/null; then
      if python3 -c 'import sys, zipfile; z=zipfile.ZipFile(sys.argv[1]); sys.exit(0 if any(n.endswith(".dex") for n in z.namelist()) else 1)' "$apk_file" 2>/dev/null; then
        has_dex=1
      fi
    elif command -v unzip &>/dev/null; then
      if unzip -l "$apk_file" 2>/dev/null | grep -q 'classes.*\.dex'; then
        has_dex=1
      fi
    fi
    if [ "$has_dex" -eq 1 ]; then
      rm -rf "$(dirname "$apk_file")/oat" 2>/dev/null || true
    fi
  done < <(find "$app_dir" -maxdepth 2 -type f -name "*.apk" -print0 2>/dev/null)
}

validate_and_fix_staged_configs() {
  local src_root="$1"
  local staging_dir="$2"

  command -v python3 &>/dev/null || return 0

  python3 - "$src_root" "$staging_dir" <<'PY'
import os, re, shutil, struct, sys, xml.etree.ElementTree as ET, zipfile

src_root = sys.argv[1]
staging_dir = sys.argv[2]

def get_apk_package_and_perms(apk_path):
    try:
        with zipfile.ZipFile(apk_path, "r") as zf:
            data = zf.read("AndroidManifest.xml")
    except Exception:
        return None, []
    if len(data) < 8:
        return None, []
    f_type, f_hsize, _ = struct.unpack_from("<HHI", data, 0)
    if f_type != 0x0003:
        return None, []
    pos = f_hsize
    strings = []
    pkg_name = None
    uses_perms = []
    while pos + 8 <= len(data):
        c_type, c_hsize, c_size = struct.unpack_from("<HHI", data, pos)
        if c_size < 8 or pos + c_size > len(data):
            break
        if c_type == 0x0001 and c_size >= 28:
            scount, _, flags, s_start, _ = struct.unpack_from("<IIIII", data, pos + 8)
            is_utf8 = (flags & (1 << 8)) != 0
            offsets_base = pos + c_hsize
            sp_base = pos + s_start
            for i in range(scount):
                if offsets_base + (i + 1) * 4 > pos + c_size:
                    break
                off = struct.unpack_from("<I", data, offsets_base + i * 4)[0]
                idx = sp_base + off
                try:
                    if is_utf8:
                        u16_l = data[idx]; idx += 2 if (u16_l & 0x80) else 1
                        u8_l = data[idx]; idx += 1
                        if u8_l & 0x80:
                            u8_l = ((u8_l & 0x7f) << 8) | data[idx]; idx += 1
                        strings.append(data[idx:idx + u8_l].decode("utf-8", errors="ignore"))
                    else:
                        u16_l = struct.unpack_from("<H", data, idx)[0]; idx += 2
                        if u16_l & 0x8000:
                            u16_l = ((u16_l & 0x7fff) << 16) | struct.unpack_from("<H", data, idx)[0]; idx += 2
                        strings.append(data[idx:idx + u16_l * 2].decode("utf-16le", errors="ignore"))
                except Exception:
                    strings.append("")
        elif c_type == 0x0102 and pos + c_hsize + 20 <= len(data):
            _, name_idx, attr_start, attr_size, attr_count = struct.unpack_from("<IIHHH", data, pos + c_hsize)
            tag = strings[name_idx] if name_idx < len(strings) else ""
            if tag in ("manifest", "uses-permission", "uses-permission-sdk-23"):
                attr_base = pos + c_hsize + attr_start
                attrs = {}
                for i in range(attr_count):
                    ap = attr_base + i * attr_size
                    if ap + 20 > pos + c_size:
                        break
                    _, a_name, a_raw, _, _, a_dtype, a_data = struct.unpack_from("<IIIHBBI", data, ap)
                    k = strings[a_name] if a_name < len(strings) else ""
                    v = ""
                    if a_raw != 0xFFFFFFFF and a_raw < len(strings):
                        v = strings[a_raw]
                    elif a_dtype == 0x03 and a_data < len(strings):
                        v = strings[a_data]
                    if k:
                        attrs[k] = v
                if tag == "manifest" and attrs.get("package"):
                    pkg_name = attrs["package"].strip()
                elif tag in ("uses-permission", "uses-permission-sdk-23") and attrs.get("name"):
                    uses_perms.append(attrs["name"].strip())
        pos += c_size
    return pkg_name, uses_perms

# 1. Verify privapp-permissions XMLs match exact APK package names
#    (e.g. milanf stock ImagerTuning-V5.apk uses package="com.motorola.imagertuning_V5"
#     while stock XML mistakenly specifies package="com.motorola.imagertuning5")
for part in ("product", "system_ext"):
    priv_dir = os.path.join(staging_dir, "system", part, "priv-app")
    perm_dir = os.path.join(staging_dir, "system", part, "etc", "permissions")
    if not os.path.isdir(priv_dir):
        continue
    os.makedirs(perm_dir, exist_ok=True)

    declared_pkgs = {}
    for fn in sorted(os.listdir(perm_dir)):
        if not fn.endswith(".xml"):
            continue
        fpath = os.path.join(perm_dir, fn)
        try:
            tree = ET.parse(fpath)
            for elem in tree.getroot().findall(".//privapp-permissions"):
                p = elem.attrib.get("package", "").strip()
                if p:
                    perms = [c.attrib.get("name", "").strip() for c in elem.findall("permission") if c.attrib.get("name")]
                    declared_pkgs[p] = (fpath, perms)
        except Exception:
            pass

    for root_d, _, files in os.walk(priv_dir):
        for fn in files:
            if not fn.endswith(".apk"):
                continue
            pkg, uses_perms = get_apk_package_and_perms(os.path.join(root_d, fn))
            if not pkg or pkg in declared_pkgs:
                continue
            # Check for normalized match (e.g., imagertuning_V5 vs imagertuning5)
            norm_pkg = re.sub(r"[_.\-vV]", "", pkg).lower()
            matched_perms = []
            target_xml = os.path.join(perm_dir, f"privapp-permissions-{pkg}.xml")
            for cand_pkg, (cand_xml, cand_perms) in declared_pkgs.items():
                if re.sub(r"[_.\-vV]", "", cand_pkg).lower() == norm_pkg:
                    matched_perms = cand_perms
                    target_xml = cand_xml
                    break
            if not matched_perms:
                matched_perms = [u for u in uses_perms if "IMAGER" in u or u in (
                    "android.permission.STOP_APP_SWITCHES",
                    "android.permission.WRITE_SECURE_SETTINGS",
                    "android.permission.START_ACTIVITIES_FROM_BACKGROUND",
                    "android.permission.START_FOREGROUND_SERVICES_FROM_BACKGROUND",
                    "android.permission.INTERACT_ACROSS_USERS",
                )]
            if matched_perms:
                if os.path.isfile(target_xml):
                    tree = ET.parse(target_xml)
                    r = tree.getroot()
                else:
                    r = ET.Element("permissions")
                    tree = ET.ElementTree(r)
                pp = ET.SubElement(r, "privapp-permissions", {"package": pkg})
                for mp in matched_perms:
                    ET.SubElement(pp, "permission", {"name": mp})
                ET.indent(tree, space="    ")
                tree.write(target_xml, encoding="utf-8", xml_declaration=True)
                declared_pkgs[pkg] = (target_xml, matched_perms)

# 2. Verify every library listed in staged system_ext/etc/public.libraries-*.txt exists
#    so Android libnativeloader never aborts Zygote at boot
se_etc = os.path.join(staging_dir, "system", "system_ext", "etc")
se_lib64 = os.path.join(staging_dir, "system", "system_ext", "lib64")
src_se_lib64 = os.path.join(src_root, "system_ext", "lib64")
if os.path.isdir(se_etc):
    for fn in sorted(os.listdir(se_etc)):
        if not (fn.startswith("public.libraries-") and fn.endswith(".txt")):
            continue
        p = os.path.join(se_etc, fn)
        valid = True
        with open(p, "r", encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                libname = line.strip().split()[0] if line.strip() and not line.strip().startswith("#") else ""
                if not libname:
                    continue
                staged_so = os.path.join(se_lib64, libname)
                if not os.path.isfile(staged_so):
                    src_so = os.path.join(src_se_lib64, libname)
                    if os.path.isfile(src_so):
                        os.makedirs(se_lib64, exist_ok=True)
                        shutil.copy2(src_so, staged_so)
                    else:
                        valid = False
        if not valid:
            os.remove(p)
PY
}

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
    strip_redundant_oat_if_dex_present "${staging_dir}/system/product/priv-app/${cam_folder_name}"
  fi

  # Companion AI Scene Engine
  local ai_src_dir
  ai_src_dir=$(find "${src_root}/product" -type d -name "MotCamera*AI*" 2>/dev/null | head -n1 || true)
  if [ -n "$ai_src_dir" ]; then
    local ai_folder_name="${ai_src_dir##*/}"
    cp -rf "$ai_src_dir" "${staging_dir}/system/product/app/"
    strip_redundant_oat_if_dex_present "${staging_dir}/system/product/app/${ai_folder_name}"
    log_ok "Harvested AI Scene Engine: ${ai_folder_name}"
  fi

  # Camera-only permissions, sysconfigs, init, and desktop app config
  cp -f "${src_root}/product/etc/permissions/"*com.motorola.camera* "${staging_dir}/system/product/etc/permissions/" 2>/dev/null || true
  cp -f "${src_root}/product/etc/sysconfig/"*com.motorola.camera* "${staging_dir}/system/product/etc/sysconfig/" 2>/dev/null || true
  cp -f "${src_root}/product/etc/init/"*motcamera* "${staging_dir}/system/product/etc/init/" 2>/dev/null || true
  if [ -d "${src_root}/product/etc/MotoDesktopAppConfig" ]; then
    cp -f "${src_root}/product/etc/MotoDesktopAppConfig/"*camera* "${staging_dir}/system/product/etc/MotoDesktopAppConfig/" 2>/dev/null || true
  fi

  # Shutter/focus sounds if present
  if [ -d "${src_root}/product/media/audio/ui" ]; then
    mkdir -p "${staging_dir}/system/product/media/audio/ui"
    cp -f "${src_root}/product/media/audio/ui/"camera_* "${staging_dir}/system/product/media/audio/ui/" 2>/dev/null || true
  fi

  # ----------------------------------------------------------------------------
  # 2. System_ext Partition Components (Strictly Camera / Imager / Desktop Only)
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
    if [ -n "$d" ]; then
      cp -rf "$d" "${staging_dir}/system/system_ext/priv-app/"
      strip_redundant_oat_if_dex_present "${staging_dir}/system/system_ext/priv-app/${d##*/}"
    fi
  done < <(find "${src_root}/system_ext/priv-app" -maxdepth 1 -type d -name "ImagerTuning*" -print0 2>/dev/null)

  # MotCameraDesktop app directory
  if [ -d "${src_root}/system_ext/priv-app/MotCameraDesktop" ]; then
    cp -rf "${src_root}/system_ext/priv-app/MotCameraDesktop" "${staging_dir}/system/system_ext/priv-app/"
    strip_redundant_oat_if_dex_present "${staging_dir}/system/system_ext/priv-app/MotCameraDesktop"
  fi

  # Camera/Imager/Desktop frameworks ONLY (never copy IMS/telephony jars like cmadaptor)
  for fw_pat in "*camera*" "*imager*" "*imgTuner*" "*imgtuner*"; do
    while IFS= read -r -d $'\0' fw_file; do
      [ -n "$fw_file" ] && cp -f "$fw_file" "${staging_dir}/system/system_ext/framework/"
    done < <(find "${src_root}/system_ext/framework" -maxdepth 1 -type f -name "$fw_pat" -print0 2>/dev/null)
  done

  # Camera/Imager/Desktop permissions ONLY (never copy unrelated stock privapp-permissions)
  for perm_pat in "*camera*" "*imager*" "*imgTuner*" "*imgtuner*"; do
    while IFS= read -r -d $'\0' perm_file; do
      [ -n "$perm_file" ] && cp -f "$perm_file" "${staging_dir}/system/system_ext/etc/permissions/"
    done < <(find "${src_root}/system_ext/etc/permissions" -maxdepth 1 -type f -name "$perm_pat" -print0 2>/dev/null)
  done

  # Camera/Imager public.libraries ONLY (never copy public.libraries-qti.txt!)
  for pub_pat in "public.libraries-*camera*" "public.libraries-*imager*" "public.libraries-*imagetuner*" "public.libraries-*imgTuner*" "public.libraries-*imgtuner*"; do
    while IFS= read -r -d $'\0' pub_file; do
      [ -n "$pub_file" ] && cp -f "$pub_file" "${staging_dir}/system/system_ext/etc/"
    done < <(find "${src_root}/system_ext/etc" -maxdepth 1 -type f -name "$pub_pat" -print0 2>/dev/null)
  done

  # Enable-disable criteria & sysconfigs strictly for camera/imager/motcameradesktop
  cp -f "${src_root}/system_ext/etc/enable-disable-packages/"*camera* "${staging_dir}/system/system_ext/etc/enable-disable-packages/" 2>/dev/null || true
  for sc_pat in "*camera*" "*imager*" "*imgTuner*" "*imgtuner*"; do
    while IFS= read -r -d $'\0' sc_file; do
      [ -n "$sc_file" ] && cp -f "$sc_file" "${staging_dir}/system/system_ext/etc/sysconfig/"
    done < <(find "${src_root}/system_ext/etc/sysconfig" -maxdepth 1 -type f -name "$sc_pat" -print0 2>/dev/null)
  done

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

  for base_fw in "com.motorola.motosignature" "moto-core_services" "moto-settings"; do
    if [ -f "${sys_path}/framework/${base_fw}.jar" ]; then
      cp -f "${sys_path}/framework/${base_fw}.jar" "${staging_dir}/system/framework/"
      [ -f "${sys_path}/etc/permissions/${base_fw}.xml" ] && cp -f "${sys_path}/etc/permissions/${base_fw}.xml" "${staging_dir}/system/etc/permissions/"
    fi
  done

  for lib_arch in lib64 lib; do
    if [ -d "${sys_path}/${lib_arch}" ]; then
      mkdir -p "${staging_dir}/system/${lib_arch}"
      while IFS= read -r -d $'\0' lib_file; do
        [ -n "$lib_file" ] && cp -f "$lib_file" "${staging_dir}/system/${lib_arch}/"
      done < <(find "${sys_path}/${lib_arch}" -maxdepth 1 -type f -name "motorola.hardware.camera*" -print0 2>/dev/null)
    fi
  done

  # Note: /vendor is intentionally NOT harvested or modified. LineageOS does not
  # reserve writable headroom on /vendor (read-only EROFS on sm7435/genevn, tight
  # EXT4 on sm6375/milanf), already ships motorola.hardware.camera.desktop@2.0-service
  # with proper SELinux policy, and modifying /vendor breaks VINTF SELinux labels.

  # Validate privapp-permissions package names & public.libraries-*.txt integrity
  validate_and_fix_staged_configs "$src_root" "$staging_dir"

  # Remove any empty staging directories
  find "${staging_dir}/system" -depth -type d -empty -delete 2>/dev/null || true

  log_ok "All ${CAMERA_GEN_NAME} proprietary blobs harvested successfully."
}

# ------------------------------------------------------------------------------
# 9. Companion Linux Host ADB Sideload + Auto-Log-Exporter Script Generator
# ------------------------------------------------------------------------------
generate_adb_helper_script() {
  local base_pkg_name="$1"
  local out_sh="$2"

  cat <<EOF > "$out_sh"
#!/usr/bin/env bash
DEFAULT_ZIP_NAME="${base_pkg_name}.zip"
EOF

  cat <<'EOF_ADB_SH' >> "$out_sh"
# ==============================================================================
# Moto Camera Restored — Companion Linux ADB Sideload & Diagnostic Log Collector
# Installs the DEBUG recovery ZIP via ADB and automatically saves the device's
# diagnostic install/boot log right next to the .zip file on this Linux machine!
#
# Usage:
#   ./<script>.sh                    (Sideload ZIP + export .debug.log next to ZIP)
#   ./<script>.sh "/path/to/pkg.zip" (Specify custom ZIP path)
#   ./<script>.sh --pull-only        (Skip sideload; pull log from Recovery/Android)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PULL_ONLY=0

if [ "$1" = "--pull-only" ] || [ "$1" = "--pull-log" ]; then
  PULL_ONLY=1
  shift
fi

if [ -n "$1" ] && [ -f "$1" ]; then
  ZIP_FILE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
elif [ -f "${SCRIPT_DIR}/${DEFAULT_ZIP_NAME}" ]; then
  ZIP_FILE="${SCRIPT_DIR}/${DEFAULT_ZIP_NAME}"
else
  ZIP_FILE=$(find "$SCRIPT_DIR" -maxdepth 1 -type f -name "MotoCameraRestored_*_DEBUG_Recovery_Installer.zip" 2>/dev/null | head -n1 || true)
fi

if [ -z "$ZIP_FILE" ] || [ ! -f "$ZIP_FILE" ]; then
  echo "[ERROR] Could not find debug recovery ZIP next to this script!"
  echo "        Expected: ${SCRIPT_DIR}/${DEFAULT_ZIP_NAME}"
  exit 1
fi

ZIP_DIR="$(cd "$(dirname "$ZIP_FILE")" && pwd)"
ZIP_BASE="$(basename "$ZIP_FILE" .zip)"
LOG_FILE="${ZIP_DIR}/${ZIP_BASE}.debug.log"

if ! command -v adb &>/dev/null; then
  echo "[ERROR] 'adb' was not found in PATH! Please install Android platform-tools."
  exit 1
fi

{
  echo "================================================================================"
  echo "  MOTO CAMERA RESTORED — HOST PC ADB SIDELOAD & DIAGNOSTIC LOG"
  echo "================================================================================"
  echo "Timestamp: $(date -u 2>/dev/null || date)"
  echo "Host OS:   $(uname -a 2>/dev/null || echo unknown)"
  echo "ZIP Path:  $ZIP_FILE"
  echo "Log Path:  $LOG_FILE"
  echo "--- adb version ---"
  adb version 2>&1 || true
  echo "--- initial adb devices -l ---"
  adb devices -l 2>&1 || true
  echo ""
} > "$LOG_FILE"

echo "================================================================================"
echo "  Moto Camera Restored — Debug ADB Installer & Log Collector"
echo "================================================================================"
echo "  ZIP Package: $ZIP_FILE"
echo "  Debug Log:   $LOG_FILE"
echo "================================================================================"

if [ "$PULL_ONLY" -eq 0 ]; then
  if ! adb devices 2>/dev/null | awk 'NR>1 {print $2}' | grep -qx "sideload"; then
    echo ""
    echo "[1/3] Waiting for phone in Recovery Sideload mode..."
    echo "      -> LineageOS Recovery: Tap 'Apply Update' -> 'Apply from ADB'"
    echo "      -> TWRP / OrangeFox:   Tap 'Advanced' -> 'ADB Sideload' -> Swipe"
    while ! adb devices 2>/dev/null | awk 'NR>1 {print $2}' | grep -qx "sideload"; do
      sleep 2
    done
  fi

  echo ""
  echo "[2/3] Sideloading $(basename "$ZIP_FILE")..."
  echo "      (If phone asks 'Signature verification failed. Install anyway?', tap 'Yes'!)"
  echo "================================================================================" >> "$LOG_FILE"
  echo "  ADB SIDELOAD OUTPUT" >> "$LOG_FILE"
  echo "================================================================================" >> "$LOG_FILE"
  adb sideload "$ZIP_FILE" 2>&1 | tee -a "$LOG_FILE"
  SIDELOAD_RC=${PIPESTATUS[0]}
  echo "adb sideload exit code: $SIDELOAD_RC" >> "$LOG_FILE"
fi

echo ""
echo "[3/3] Waiting for ADB connection to pull on-device diagnostic log..."
echo "      IMPORTANT (LineageOS Recovery):"
echo "        adb sideload closes USB until you re-enable ADB or boot Android."
echo "        Do ONE of the following on the phone right now:"
echo "          Option A (Recommended): Tap Back -> 'Advanced' -> 'Enable ADB'"
echo "          Option B (Booted OS):   Tap 'Reboot system now' (with USB Debugging on)"
echo "      (TWRP / OrangeFox reconnects automatically in ~3 seconds.)"
echo ""

TMP_PULL="${ZIP_DIR}/.motocamera_pull_$$.tmp"
PULLED_OK=0
DETECTED_MODE=""

for _ in $(seq 1 90); do
  STATE_LINE=$(adb devices 2>/dev/null | awk 'NR>1 && $2 != "" {print $2; exit}')
  if [ "$STATE_LINE" = "recovery" ]; then
    DETECTED_MODE="recovery"
    break
  elif [ "$STATE_LINE" = "device" ]; then
    DETECTED_MODE="device"
    break
  elif [ "$STATE_LINE" = "unauthorized" ]; then
    echo "      [!] Phone shows 'unauthorized' — tap 'Allow USB debugging' on phone screen!"
  fi
  sleep 2
done

if [ "$DETECTED_MODE" = "recovery" ]; then
  echo "[OK] Connected to phone in Recovery mode! Pulling diagnostic logs..."
  if adb pull /tmp/motocamera_debug.log "$TMP_PULL" >/dev/null 2>&1 && [ -s "$TMP_PULL" ]; then
    {
      echo ""
      echo "================================================================================"
      echo "  PULLED ON-DEVICE INSTALLER LOG (/tmp/motocamera_debug.log)"
      echo "================================================================================"
      cat "$TMP_PULL"
    } >> "$LOG_FILE"
    rm -f "$TMP_PULL"
    PULLED_OK=1
  fi
  {
    echo ""
    echo "================================================================================"
    echo "  RECOVERY LOG TAIL (/tmp/recovery.log)"
    echo "================================================================================"
    adb shell "tail -n 200 /tmp/recovery.log 2>/dev/null" 2>&1 || true
  } >> "$LOG_FILE"
elif [ "$DETECTED_MODE" = "device" ]; then
  echo "[OK] Connected to booted Android OS! Pulling persistent install log & boot/camera logcat..."
  if adb pull /system_ext/etc/motocamera_install_debug.log "$TMP_PULL" >/dev/null 2>&1 && [ -s "$TMP_PULL" ]; then
    {
      echo ""
      echo "================================================================================"
      echo "  PULLED PERSISTENT INSTALLER LOG (/system_ext/etc/motocamera_install_debug.log)"
      echo "================================================================================"
      cat "$TMP_PULL"
    } >> "$LOG_FILE"
    rm -f "$TMP_PULL"
    PULLED_OK=1
  fi
  {
    echo ""
    echo "================================================================================"
    echo "  ANDROID RUNTIME DEVICE STATE & FILTERED CAMERA / BOOT LOGCAT"
    echo "================================================================================"
    echo "sys.boot_completed=$(adb shell getprop sys.boot_completed 2>/dev/null)"
    echo "ro.build.display.id=$(adb shell getprop ro.build.display.id 2>/dev/null)"
    echo "--- Installed Moto packages ---"
    adb shell "pm list packages -f | grep -iE 'motorola|camera|imager'" 2>&1 || true
    echo "--- Filtered logcat (Fatal / SELinux / Camera / Imager / VINTF) ---"
    adb logcat -d 2>/dev/null | grep -iE "FATAL|AndroidRuntime|IllegalStateException|PermissionManager|PackageManager|SELinux|avc:|nativeloader|vintf|CameraService|MotCamera|ImagerTuning|imgtuner|motorola\.hardware\.camera" | tail -n 400 || true
  } >> "$LOG_FILE"
else
  echo "[WARN] Timed out waiting for post-sideload ADB connection (180s)." | tee -a "$LOG_FILE"
  echo "       You can still pull the log anytime later by running:"
  echo "         \"$0\" --pull-only"
fi

rm -f "$TMP_PULL" 2>/dev/null || true
echo ""
echo "================================================================================"
if [ "$PULLED_OK" -eq 1 ]; then
  echo "  [SUCCESS] Diagnostic debug log saved right next to the ZIP:"
else
  echo "  [SAVED] Host sideload/runtime log saved right next to the ZIP:"
fi
echo "  --> $LOG_FILE"
echo "================================================================================"
EOF_ADB_SH

  chmod +x "$out_sh" 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# 10. Recovery Package Assembly (Debug Edition)
# ------------------------------------------------------------------------------
build_recovery_package() {
  local staging_dir="$1"
  local output_dir="$2"
  local build_tmp="$3"
  local camera_prop="$4"

  local abs_output_dir=""
  if mkdir -p "$output_dir" 2>/dev/null; then
    abs_output_dir="$(cd "$output_dir" && pwd)"
  else
    abs_output_dir="$output_dir"
  fi

  log_info "Assembling DEBUG flashable recovery installer for ${DEVICE_MODEL} (${DEVICE_CODENAME})..."
  local rec_build="${build_tmp}/recovery_build"
  rm -rf "$rec_build"
  mkdir -p "$rec_build"

  # Copy base recovery scaffolding templates, then overlay diagnostic update-binary
  cp -rf "${TEMPLATES_DIR}/"* "$rec_build/"
  mkdir -p "${rec_build}/META-INF/com/google/android"
  cp -f "$DEBUG_UPDATE_BINARY" "${rec_build}/META-INF/com/google/android/update-binary"
  chmod +x "${rec_build}/META-INF/com/google/android/update-binary"

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

  # Determine sanitized package base name including firmware build version & DEBUG tag
  local clean_build_ver
  clean_build_ver=$(echo "$ROM_BUILD_VERSION" | sed 's/[^a-zA-Z0-9._-]/_/g' | sed 's/__*/_/g')
  local helper_prefix=""
  if [ -n "$clean_build_ver" ] && [ "$clean_build_ver" != "UNKNOWN" ]; then
    BASE_PACKAGE_NAME="MotoCameraRestored_${DEVICE_CODENAME}_${clean_build_ver}_DEBUG_Recovery_Installer"
    helper_prefix="MotoCameraRestored_${DEVICE_CODENAME}_${clean_build_ver}_DEBUG_ADB_Install"
  else
    BASE_PACKAGE_NAME="MotoCameraRestored_${DEVICE_CODENAME}_DEBUG_Recovery_Installer"
    helper_prefix="MotoCameraRestored_${DEVICE_CODENAME}_DEBUG_ADB_Install"
  fi

  local tmp_zip="${build_tmp}/${BASE_PACKAGE_NAME}.zip"
  local tmp_info="${build_tmp}/${BASE_PACKAGE_NAME}.txt"
  local tmp_adb_sh="${build_tmp}/${helper_prefix}.sh"

  # Package flashable recovery ZIP inside native temp workdir first
  rm -f "$tmp_zip"
  (cd "$rec_build" && zip -r9q "$tmp_zip" .)

  # Generate companion Linux (.sh) ADB sideload + log export script
  generate_adb_helper_script "$BASE_PACKAGE_NAME" "$tmp_adb_sh"

  # Extract list of harvested files from staging with version info
  local extracted_files_list=""
  local extracted_count=0
  if [ -d "${staging_dir}/system" ]; then
    if command -v python3 &>/dev/null; then
      extracted_files_list=$(python3 -c '
import os, sys, re, struct, zipfile

staging_dir = sys.argv[1]
sys_root = os.path.join(staging_dir, "system")

def parse_axml_version(data):
    if len(data) < 8:
        return None
    f_type, f_hsize, _ = struct.unpack_from("<HHI", data, 0)
    if f_type != 0x0003:
        return None
    pos = f_hsize
    strings = []
    res_ids = []
    while pos + 8 <= len(data):
        c_type, c_hsize, c_size = struct.unpack_from("<HHI", data, pos)
        if c_size < 8 or pos + c_size > len(data):
            break
        if c_type == 0x0001 and c_size >= 28:
            scount, _, flags, s_start, _ = struct.unpack_from("<IIIII", data, pos + 8)
            is_utf8 = (flags & (1 << 8)) != 0
            offsets_base = pos + c_hsize
            sp_base = pos + s_start
            for i in range(scount):
                if offsets_base + (i + 1) * 4 > pos + c_size:
                    break
                off = struct.unpack_from("<I", data, offsets_base + i * 4)[0]
                idx = sp_base + off
                try:
                    if is_utf8:
                        u16_l = data[idx]; idx += 2 if (u16_l & 0x80) else 1
                        u8_l = data[idx]; idx += 1
                        if u8_l & 0x80:
                            u8_l = ((u8_l & 0x7f) << 8) | data[idx]; idx += 1
                        strings.append(data[idx:idx + u8_l].decode("utf-8", errors="ignore"))
                    else:
                        u16_l = struct.unpack_from("<H", data, idx)[0]; idx += 2
                        if u16_l & 0x8000:
                            u16_l = ((u16_l & 0x7fff) << 16) | struct.unpack_from("<H", data, idx)[0]; idx += 2
                        strings.append(data[idx:idx + u16_l * 2].decode("utf-16le", errors="ignore"))
                except Exception:
                    strings.append("")
        elif c_type == 0x0180:
            cnt = (c_size - c_hsize) // 4
            res_ids = list(struct.unpack_from(f"<{cnt}I", data, pos + c_hsize))
        elif c_type == 0x0102 and pos + c_hsize + 20 <= len(data):
            _, name_idx, attr_start, attr_size, attr_count = struct.unpack_from("<IIHHH", data, pos + c_hsize)
            if name_idx < len(strings) and strings[name_idx] == "manifest":
                attr_base = pos + c_hsize + attr_start
                for i in range(attr_count):
                    ap = attr_base + i * attr_size
                    if ap + 20 > pos + c_size:
                        break
                    _, a_name, a_raw, _, _, a_dtype, a_data = struct.unpack_from("<IIIHBBI", data, ap)
                    is_ver_name = (a_name < len(res_ids) and res_ids[a_name] == 0x0101021c) or (a_name < len(strings) and strings[a_name] == "versionName")
                    if is_ver_name:
                        if a_raw != 0xFFFFFFFF and a_raw < len(strings) and strings[a_raw]:
                            return strings[a_raw].strip()
                        if a_dtype == 0x03 and a_data < len(strings) and strings[a_data]:
                            return strings[a_data].strip()
                break
        pos += c_size
    return None

def get_file_version(filepath):
    filename = os.path.basename(filepath)

    m = re.search(r"@([0-9]+(?:\.[0-9]+)+)", filename)
    if m:
        return f"v{m.group(1)}"
    m_v = re.search(r"[-_]v([0-9]+(?:\.[0-9]+)*)", filename, re.IGNORECASE)
    if m_v:
        return f"v{m_v.group(1)}"
    m_so = re.search(r"\.so\.([0-9]+(?:\.[0-9]+)*)$", filename)
    if m_so:
        return f"v{m_so.group(1)}"

    if filename.endswith(".apk"):
        try:
            with zipfile.ZipFile(filepath, "r") as z:
                if "AndroidManifest.xml" in z.namelist():
                    ver_str = parse_axml_version(z.read("AndroidManifest.xml"))
                    if ver_str:
                        return ver_str if ver_str.lower().startswith("v") else f"v{ver_str}"
                for dex_name in ["classes.dex", "classes2.dex"]:
                    if dex_name in z.namelist():
                        dex = z.read(dex_name)
                        m_dex = re.findall(rb"([0-9]+\.[0-9]+(?:\.[0-9]+)+)", dex)
                        for match in m_dex:
                            s = match.decode("ascii", errors="ignore")
                            if len(s) >= 3 and not s.startswith("0.0.0"):
                                return f"v{s}"
        except Exception:
            pass

    if filename.endswith(".jar"):
        try:
            with zipfile.ZipFile(filepath, "r") as z:
                if "META-INF/MANIFEST.MF" in z.namelist():
                    mf = z.read("META-INF/MANIFEST.MF").decode("utf-8", errors="ignore")
                    m_mf = re.search(r"(?:Implementation-Version|Bundle-Version|Specification-Version):\s*([0-9]+(?:\.[0-9]+)*)", mf, re.IGNORECASE)
                    if m_mf:
                        return f"v{m_mf.group(1)}"
        except Exception:
            pass

    if filename.endswith(".xml"):
        try:
            with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
                m_xml = re.search(r"<version>([0-9]+(?:\.[0-9]+)+)</version>", content)
                if m_xml:
                    return f"v{m_xml.group(1)}"
        except Exception:
            pass

    return None

if not os.path.exists(sys_root):
    sys.exit(0)

file_list = []
for root, dirs, files in os.walk(sys_root):
    for f in sorted(files):
        p = os.path.join(root, f)
        rel_path = "/" + os.path.relpath(p, staging_dir)
        ver = get_file_version(p)
        if ver:
            file_list.append(f"{rel_path}  [{ver}]")
        else:
            file_list.append(rel_path)

file_list.sort()
for item in file_list:
    print(item)
' "$staging_dir" 2>/dev/null || true)
    fi
    if [ -z "$extracted_files_list" ]; then
      extracted_files_list=$(cd "${staging_dir}" && find system -type f | sort | sed 's|^system|/system|' || true)
    fi
    extracted_count=$(printf "%s\n" "$extracted_files_list" | awk 'NF{c++} END{print c+0}')
  fi

  # Write metadata summary text and harvested file manifest
  cat <<EOF > "$tmp_info"
================================================================================
        Moto Camera Restored — DEBUG Recovery Package Build Manifest            
================================================================================
Target Device:
  Model:                ${DEVICE_MODEL}
  Codename:             ${DEVICE_CODENAME}
  Hardware Platform:    ${PLATFORM_SOC}

Firmware Build Info:
  Android Version:      ${ANDROID_VERSION} (API SDK ${SDK_LEVEL})
  Stock Firmware Build: ${ROM_BUILD_VERSION}
  Stock Build ID:       ${BUILD_ID}

Restored Camera Suite:
  Generation:           ${CAMERA_GEN_NAME} (${CAMERA_VER})
  Template Module:      templates/${CAMERA_GEN}_debug (Diagnostic Logging Mode)

Package Outputs:
  Debug Recovery ZIP:   ${BASE_PACKAGE_NAME}.zip
  Build Manifest:       ${BASE_PACKAGE_NAME}.txt
  Linux ADB Tool:       ${helper_prefix}.sh
  Expected Debug Log:   ${BASE_PACKAGE_NAME}.debug.log
  Build Timestamp:      $(date -u +"%Y-%m-%d %H:%M:%S UTC")
  Extracted Files:      ${extracted_count} harvested from stock firmware
================================================================================

Harvested Files Extracted from Stock Firmware:
--------------------------------------------------------------------------------
${extracted_files_list:-  (None)}
================================================================================
EOF

  REC_ZIP="${abs_output_dir}/${BASE_PACKAGE_NAME}.zip"
  INFO_FILE="${abs_output_dir}/${BASE_PACKAGE_NAME}.txt"
  ADB_SH_FILE="${abs_output_dir}/${helper_prefix}.sh"

  if mkdir -p "$abs_output_dir" 2>/dev/null && \
     cp -f "$tmp_zip" "$REC_ZIP" 2>/dev/null && \
     cp -f "$tmp_info" "$INFO_FILE" 2>/dev/null && \
     cp -f "$tmp_adb_sh" "$ADB_SH_FILE" 2>/dev/null; then
    chmod +x "$ADB_SH_FILE" 2>/dev/null || true
  else
    local fallback_out="${HOME}/Downloads/MotoCameraRestored_Output"
    if ! mkdir -p "$fallback_out" 2>/dev/null; then
      fallback_out="/var/tmp/MotoCameraRestored_Output"
      mkdir -p "$fallback_out"
    fi
    REC_ZIP="${fallback_out}/${BASE_PACKAGE_NAME}.zip"
    INFO_FILE="${fallback_out}/${BASE_PACKAGE_NAME}.txt"
    ADB_SH_FILE="${fallback_out}/${helper_prefix}.sh"
    cp -f "$tmp_zip" "$REC_ZIP"
    cp -f "$tmp_info" "$INFO_FILE"
    cp -f "$tmp_adb_sh" "$ADB_SH_FILE"
    chmod +x "$ADB_SH_FILE" 2>/dev/null || true
    log_warn "Could not write new files to '${abs_output_dir}' (filesystem full or NTFS MFT exhausted)."
    log_warn "Saved compiled debug recovery package & Linux ADB helper to fallback directory: ${fallback_out}"
  fi

  log_ok "Debug Recovery ZIP created: $REC_ZIP ($(du -h "$REC_ZIP" | cut -f1))"
  log_ok "Build manifest saved:       $INFO_FILE"
  log_ok "Linux ADB Installer:        $ADB_SH_FILE"
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
    chmod -R u+w "$WORK_DIR" 2>/dev/null || true
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
  local abs_out_dir=""
  if mkdir -p "$out_dir" 2>/dev/null; then
    abs_out_dir="$(cd "$out_dir" && pwd)"
  else
    local parent_out
    parent_out="$(cd "$(dirname "$out_dir")" 2>/dev/null && pwd || pwd)"
    abs_out_dir="${parent_out}/$(basename "$out_dir")"
  fi

  # Prefer native Linux temp storage (/var/tmp or $TMPDIR) when >=15GB is free
  # to avoid slow FUSE/NTFS/WSL I/O and NTFS $MFT record exhaustion during EROFS unpack
  WORK_DIR=""
  for candidate_tmp in "/var/tmp" "${TMPDIR:-/tmp}"; do
    if [ -d "$candidate_tmp" ] && [ -w "$candidate_tmp" ]; then
      local avail_kb
      avail_kb=$(df -Pk "$candidate_tmp" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
      if [ "${avail_kb:-0}" -ge 15728640 ]; then
        WORK_DIR=$(mktemp -d "${candidate_tmp}/motocamera_build_XXXXXX" 2>/dev/null || echo "")
        [ -n "$WORK_DIR" ] && break
      fi
    fi
  done

  if [ -z "$WORK_DIR" ]; then
    local base_work_dir="${abs_out_dir}/.build_tmp"
    mkdir -p "$base_work_dir" 2>/dev/null || true
    WORK_DIR="$(mktemp -d "${base_work_dir}/motocamera_build_XXXXXX" 2>/dev/null || mktemp -d /tmp/motocamera_build_XXXXXX)"
  fi

  log_info "Working directory initialized: $WORK_DIR"

  get_firmware_path "$cli_input"
  extract_firmware "$FIRMWARE_INPUT" "$WORK_DIR"

  profile_device "$FIRMWARE_ROOT"
  detect_camera_generation "$FIRMWARE_ROOT"

  ensure_templates "$WORK_DIR" "$CAMERA_GEN" "$CAMERA_GEN_NAME" "$cli_template"
  ensure_debug_update_binary "$WORK_DIR" "$CAMERA_GEN" "$CAMERA_GEN_NAME" "$cli_template"

  local camera_prop="${WORK_DIR}/motocamera.prop"
  harvest_camera_properties "$FIRMWARE_ROOT" "$camera_prop"

  local staging_dir="${WORK_DIR}/staging"
  harvest_blobs "$FIRMWARE_ROOT" "$staging_dir" "$CAMERA_GEN"

  build_recovery_package "$staging_dir" "$abs_out_dir" "$WORK_DIR" "$camera_prop"

  echo ""
  echo -e "${C_BOLD}${C_GREEN}================================================================================"
  echo "            DEBUG Recovery Package & ADB Log Tool Compiled Successfully!        "
  echo -e "================================================================================${C_RESET}"
  echo ""
  echo "Target Device:"
  echo "  --> Model:           ${DEVICE_MODEL}"
  echo "  --> Codename:        ${DEVICE_CODENAME}"
  echo "  --> Stock Build:     ${ROM_BUILD_VERSION}"
  echo "  --> Generation:      ${CAMERA_GEN_NAME} (${CAMERA_VER})"
  echo "  --> Debug Module:    templates/${CAMERA_GEN}_debug"
  echo ""
  echo "Package Outputs:"
  echo "  --> Debug ZIP:       ${REC_ZIP}"
  echo "  --> Manifest:        ${INFO_FILE}"
  echo "  --> Linux ADB Tool:  ${ADB_SH_FILE}"
  echo ""
  echo "How to install via ADB on Linux & dump a .debug.log next to the ZIP:"
  echo "  1. Keep BOTH the .zip AND '${ADB_SH_FILE##*/}' in the same folder."
  echo "  2. Boot phone into Recovery -> 'Apply Update' -> 'Apply from ADB'."
  echo "  3. Run:"
  echo "       ./${ADB_SH_FILE##*/}"
  echo "  4. After sideload completes, tap 'Advanced -> Enable ADB' in Lineage Recovery"
  echo "     (or reboot into Android with USB Debugging on). The script automatically saves:"
  echo "       ${REC_ZIP%.zip}.debug.log"
  echo "     right next to the .zip!"
  echo ""
  echo "Manual ADB pull fallback (if flashed via plain 'adb sideload'):"
  echo "  --> In Recovery:     adb pull /tmp/motocamera_debug.log ."
  echo "  --> In Android OS:   adb pull /system_ext/etc/motocamera_install_debug.log ."
  echo "  --> Local SD/USB:    <ZipName>.debug.log is written next to the .zip automatically!"
  echo ""
}

main "$@"
