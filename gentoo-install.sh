#!/usr/bin/env bash
# =============================================================================
# Gentoo Interactive Installer (TUI/CLI)
#   Modular, feature-rich Gentoo Linux installer with dialog/whiptail support
#
# Features:
#   * Interactive TUI menu (dialog/whiptail with fallback to select)
#   * Multiple init systems: OpenRC / systemd
#   * Multiple desktop environments: KDE, Hyprland, Niri, Mangowm, minimal
#   * Flexible kernel selection: distribution-kernel-bin / gentoo-kernel / sources
#   * Disk partitioning: auto/manual, ext4/btrfs/xfs
#   * GPU support: NVIDIA, AMD, Intel with auto-detection
#   * Binary packages (binhost) support on/off toggle
#   * Kernel compilation options: menuconfig / localyesconfig / defconfig
#   * Package masking: stable vs testing (~amd64)
# =============================================================================
set -Eeuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# =============================================================================
# Constants & Globals
# =============================================================================
readonly MNT="/mnt/gentoo"
readonly CHROOT_SCRIPT="$MNT/root/install_in_chroot.sh"
LIVE_LOG="/tmp/gentoo-install-$(date +%Y%m%d-%H%M%S).log"
readonly LIVE_LOG

# Dialog/TUI backend selection
TUI_BACKEND=""  # will be set to dialog or whiptail

# Configuration variables (all collected during interactive phase)
INIT_SYSTEM="openrc"           # openrc | systemd
DESKTOP_PROFILE="kde"          # kde | hyprland | niri | mangowm | minimal
DISPLAY_PROTOCOL="wayland"     # wayland | x11
BOOT_TYPE="uefi"               # uefi | bios
FS_TYPE="ext4"                 # ext4 | btrfs | xfs
DISK=""
ROOT_GB=30
HOSTNAME=""
USERNAME=""
TIMEZONE="UTC"
KEYMAP="us"
BLUETOOTH=0
USE_BINHOST=0                  # 0 = no, 1 = yes (use binary packages)
KERNEL_TYPE="distribution-kernel-bin"  # distribution-kernel-bin | gentoo-kernel | gentoo-sources
KERNEL_COMPILE="none"          # none | menuconfig | localyesconfig | defconfig (only for sources)
PACKAGE_POLICY="stable"        # stable | testing
VIDEO_CARDS=""
HAVE_NVIDIA=0
GPU_NEEDS_FIRMWARE=0
IS_VM=0
VIRT="none"

# Partitions (will be set during partitioning)
PEFI=""
PROOT=""
PSWAP=""
SWAP_MIB=0
DISK_GIB=0

# Status tracking
STATUS_OK=0; STATUS_INSTALLED=0; STATUS_NA=0; STATUS_FAILED=0
STATUS_LINES=()
MOUNTS_ACTIVE=0

# Passwords (never echoed)
ROOT_PASS=""
USER_PASS=""

# =============================================================================
# Logging & Error Handling
# =============================================================================
ts()   { date '+%H:%M:%S'; }
log()  { printf '[%s] %s\n' "$(ts)" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$(ts)" "$*"; }
step() { printf '\n=== %s ===\n' "$*"; }
die()  { printf '\n[FATAL] %s\n' "$*" >&2; exit 1; }

on_err() {
  local rc=$1 line=$2 cmd=$3
  printf '\n[FATAL] command failed (exit %s) at line %s of %s\n[FATAL]     %s\n' \
    "$rc" "$line" "${BASH_SOURCE[0]##*/}" "$cmd" >&2
  printf '[FATAL] full log: %s\n' "$LIVE_LOG" >&2
}
trap 'on_err $? $LINENO "$BASH_COMMAND"' ERR

cleanup() {
  local rc=$?
  trap - EXIT INT TERM ERR
  if ((MOUNTS_ACTIVE)); then
    log "unmounting target filesystems"
    sync || true
    umount -R "$MNT/boot"      2>/dev/null || true
    umount -R "$MNT/home"      2>/dev/null || true
    umount -R "$MNT/var"       2>/dev/null || true
    umount -R "$MNT/tmp"       2>/dev/null || true
    umount -R "$MNT/.snapshots" 2>/dev/null || true
    umount -R "$MNT/proc"      2>/dev/null || true
    umount -R "$MNT/sys"       2>/dev/null || true
    umount -R "$MNT/dev"       2>/dev/null || true
    umount -R "$MNT"           2>/dev/null || umount -l "$MNT" 2>/dev/null || true
    swapoff "${PSWAP:-}"       2>/dev/null || true
  fi
  if ((rc != 0)); then
    printf '\n[!] Installation did NOT complete (exit %s). The target may be incomplete.\n' "$rc" >&2
    printf '[!] Log: %s\n' "$LIVE_LOG" >&2
    printf '[!] Do NOT reboot expecting a working system.\n' >&2
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'printf "\n[!] Interrupted by signal.\n" >&2; exit 130' INT TERM

record() {
  local st=$1 desc=$2 detail=${3:-}
  case "$st" in
    OK)        STATUS_OK=$((STATUS_OK + 1)) ;;
    INSTALLED) STATUS_INSTALLED=$((STATUS_INSTALLED + 1)) ;;
    N/A)       STATUS_NA=$((STATUS_NA + 1)) ;;
    FAILED)    STATUS_FAILED=$((STATUS_FAILED + 1)) ;;
    *) die "record(): bad status '$st'" ;;
  esac
  STATUS_LINES+=("$(printf '%-10s %-40s %s' "$st" "$desc" "$detail")")
  printf '[%s] %-10s %s %s\n' "$(ts)" "$st" "$desc" "${detail}"
}

print_status_table() {
  printf '\n%-10s %-40s %s\n' "STATUS" "CHECK" "DETAIL"
  printf '%s\n' "--------------------------------------------------------------------------"
  local l
  for l in "${STATUS_LINES[@]}"; do printf '%s\n' "$l"; done
  printf '%s\n' "--------------------------------------------------------------------------"
  printf 'OK: %s   INSTALLED: %s   N/A: %s   FAILED: %s\n' \
    "$STATUS_OK" "$STATUS_INSTALLED" "$STATUS_NA" "$STATUS_FAILED"
}

# Capture output to log
exec > >(tee -a "$LIVE_LOG") 2>&1

# =============================================================================
# TUI Backend Detection & Menu Functions
# =============================================================================
setup_tui_backend() {
  if command -v dialog >/dev/null 2>&1; then
    TUI_BACKEND="dialog"
  elif command -v whiptail >/dev/null 2>&1; then
    TUI_BACKEND="whiptail"
  else
    TUI_BACKEND="select"
  fi
  log "TUI backend: $TUI_BACKEND"
}

menu_dialog() {
  local title="$1" height="$2" width="$3"
  shift 3
  local items=("$@")

  case "$TUI_BACKEND" in
    dialog)
      dialog --title "$title" --menu "Select an option:" "$height" "$width" $((height - 8)) \
        "${items[@]}" 2>&1 | head -n 1
      ;;
    whiptail)
      whiptail --title "$title" --menu "Select an option:" "$height" "$width" $((height - 8)) \
        "${items[@]}" 2>&1
      ;;
    select)
      local choice idx=0
      printf '\n=== %s ===\n' "$title"
      # Extract labels from items array (skip values, take only labels)
      local labels=()
      for ((i=1; i<${#items[@]}; i+=2)); do
        labels+=("${items[$((i))]}")
      done
      select choice in "${labels[@]}"; do
        [[ -n "$choice" ]] && printf '%s' "$choice"
        break
      done
      ;;
  esac
}

menu_checklist() {
  local title="$1" height="$2" width="$3"
  shift 3
  local items=("$@")

  case "$TUI_BACKEND" in
    dialog)
      dialog --title "$title" --checklist "Select options:" "$height" "$width" $((height - 8)) \
        "${items[@]}" 2>&1
      ;;
    whiptail)
      whiptail --title "$title" --checklist "Select options:" "$height" "$width" $((height - 8)) \
        "${items[@]}" 2>&1
      ;;
    select)
      printf '\n=== %s ===\n' "$title"
      printf 'Enter space-separated numbers: '
      read -r choice
      printf '%s' "$choice"
      ;;
  esac
}

input_dialog() {
  local title="$1" text="$2" default="${3:-}"

  case "$TUI_BACKEND" in
    dialog)
      dialog --title "$title" --inputbox "$text" 10 60 "$default" 2>&1 || true
      ;;
    whiptail)
      whiptail --title "$title" --inputbox "$text" 10 60 "$default" 2>&1
      ;;
    select)
      printf '%s [%s]: ' "$text" "$default"
      read -r choice
      printf '%s' "${choice:-$default}"
      ;;
  esac
}

yesno_dialog() {
  local title="$1" text="$2"
  local response

  case "$TUI_BACKEND" in
    dialog)
      if dialog --title "$title" --yesno "$text" 10 60 2>&1; then
        printf 'yes'
      else
        printf 'no'
      fi
      ;;
    whiptail)
      if whiptail --title "$title" --yesno "$text" 10 60 2>&1; then
        printf 'yes'
      else
        printf 'no'
      fi
      ;;
    select)
      printf '%s [y/N]: ' "$text"
      read -r response
      if [[ "${response,,}" =~ ^y ]]; then
        printf 'yes'
      else
        printf 'no'
      fi
      ;;
  esac
}

msgbox() {
  local title="$1" text="$2"
  case "$TUI_BACKEND" in
    dialog)
      dialog --title "$title" --msgbox "$text" 10 60 2>&1
      ;;
    whiptail)
      whiptail --title "$title" --msgbox "$text" 10 60 2>&1
      ;;
    select)
      printf '\n=== %s ===\n%s\n' "$title" "$text"
      ;;
  esac
}

# =============================================================================
# Preflight Checks
# =============================================================================
preflight_checks() {
  step "Preflight Checks"

  [[ $EUID -eq 0 ]] || die "Run as root from the Gentoo live environment"

  for c in parted partprobe mkfs.ext4 mkfs.btrfs mkfs.xfs mkfs.vfat mkswap swapon swapoff \
         wget curl tar lsblk blkid findmnt mountpoint mount umount blockdev \
         chroot sha512sum sed awk sort tee find; do
    command -v "$c" >/dev/null 2>&1 ||
      die "missing host tool: $c"
  done

  log "log file: $LIVE_LOG"
  record OK "preflight checks" "all required tools present"
}

# =============================================================================
# Hardware Detection
# =============================================================================
detect_virt() {
  local pname="" svendor="" blob=""
  [[ -r /sys/class/dmi/id/product_name ]] && pname=$(</sys/class/dmi/id/product_name)
  [[ -r /sys/class/dmi/id/sys_vendor  ]] && svendor=$(</sys/class/dmi/id/sys_vendor)
  blob="${pname,,}|${svendor,,}"
  case "$blob" in
    *virtualbox*|*innotek*)        printf 'virtualbox' ;;
    *vmware*)                      printf 'vmware' ;;
    *qemu*|*"kvm"*)                printf 'qemu' ;;
    *"virtual machine"*)           printf 'hyperv' ;;
    *)
      if [[ -r /sys/hypervisor/type ]]; then
        case "$(</sys/hypervisor/type)" in
          xen) printf 'xen' ;;
          *)   printf 'none' ;;
        esac
      else
        printf 'none'
      fi
      ;;
  esac
}

detect_gpus() {
  local GPU_FAMILIES=()
  shopt -s nullglob
  for d in /sys/class/drm/card*/device; do
    [[ "${d#/sys/class/drm/}" =~ ^card[0-9]+/device$ ]] || continue
    [[ -r "$d/vendor" ]] || continue
    local vendor=$(<"$d/vendor")
    local fam=""
    case "$vendor" in
      0x1002) fam="amd" ;;
      0x8086) fam="intel" ;;
      0x10de) fam="nvidia" ;;
      0x15ad) fam="vmware-gpu" ;;
      0x80ee) fam="vbox-gpu" ;;
      0x1b36) fam="qxl" ;;
      0x1234) fam="bochs" ;;
      0x1af4) fam="virtio-gpu" ;;
      *)      fam="unknown" ;;
    esac
    GPU_FAMILIES+=("$fam")
  done
  shopt -u nullglob

  if ((${#GPU_FAMILIES[@]})); then
    printf '%s\n' "${GPU_FAMILIES[@]}" | sort -u
  fi
}

hardware_detection() {
  step "Hardware Detection"

  VIRT=$(detect_virt)
  log "Virtualization: $VIRT"

  if [[ "$VIRT" != "none" ]]; then
    IS_VM=1
  fi

  record OK "virtualization detection" "$VIRT"

  # GPU detection
  if [[ $(yesno_dialog "GPU Detection" "Auto-detect graphics hardware?") == "yes" ]]; then
    VIDEO_CARDS=$(detect_gpus | xargs)
    if [[ -n "$VIDEO_CARDS" ]]; then
      log "Detected GPUs: $VIDEO_CARDS"
      record OK "GPU detection" "$VIDEO_CARDS"
    else
      warn "No GPUs detected, will use profile default"
      record OK "GPU detection" "none (profile default)"
    fi
  else
    msgbox "GPU Selection" "Manual GPU selection will be shown next"
  fi
}

# =============================================================================
# Interactive Configuration Menu
# =============================================================================
config_init_system() {
  local choice
  choice=$(menu_dialog "Init System" 15 60 \
    "1" "OpenRC (default, lightweight)" \
    "2" "systemd (featureful)")

  case "$choice" in
    1|OpenRC*) INIT_SYSTEM="openrc" ;;
    2|systemd*) INIT_SYSTEM="systemd" ;;
    *) INIT_SYSTEM="openrc" ;;
  esac

  log "Init system: $INIT_SYSTEM"
}

config_desktop() {
  local choice
  choice=$(menu_dialog "Desktop Environment" 15 60 \
    "1" "KDE Plasma (full-featured)" \
    "2" "Hyprland (Wayland tiling WM)" \
    "3" "Niri (Wayland compositor)" \
    "4" "MangoWM (lightweight tiling)" \
    "5" "Minimal (no DE/WM, cli only)")

  case "$choice" in
    1) DESKTOP_PROFILE="kde"; DISPLAY_PROTOCOL="wayland" ;;
    2) DESKTOP_PROFILE="hyprland"; DISPLAY_PROTOCOL="wayland" ;;
    3) DESKTOP_PROFILE="niri"; DISPLAY_PROTOCOL="wayland" ;;
    4) DESKTOP_PROFILE="mangowm"; DISPLAY_PROTOCOL="wayland" ;;
    5) DESKTOP_PROFILE="minimal"; DISPLAY_PROTOCOL="x11" ;;
    *) DESKTOP_PROFILE="kde"; DISPLAY_PROTOCOL="wayland" ;;
  esac

  log "Desktop profile: $DESKTOP_PROFILE, protocol: $DISPLAY_PROTOCOL"
}

config_kernel() {
  local choice
  choice=$(menu_dialog "Kernel Selection" 15 60 \
    "1" "distribution-kernel-bin (precompiled, fastest)" \
    "2" "gentoo-kernel (compile on target, flexible)" \
    "3" "gentoo-sources (manual menuconfig required)")

  case "$choice" in
    1) KERNEL_TYPE="distribution-kernel-bin"; KERNEL_COMPILE="none" ;;
    2) KERNEL_TYPE="gentoo-kernel"; KERNEL_COMPILE="localyesconfig" ;;
    3) KERNEL_TYPE="gentoo-sources"; KERNEL_COMPILE="menuconfig" ;;
    *) KERNEL_TYPE="distribution-kernel-bin"; KERNEL_COMPILE="none" ;;
  esac

  if [[ "$KERNEL_TYPE" == "gentoo-sources" ]]; then
    local kc
    kc=$(menu_dialog "Kernel Compilation" 12 60 \
      "1" "menuconfig (interactive)" \
      "2" "localyesconfig (based on running kernel)" \
      "3" "defconfig (minimal defaults)")
    case "$kc" in
      1) KERNEL_COMPILE="menuconfig" ;;
      2) KERNEL_COMPILE="localyesconfig" ;;
      3) KERNEL_COMPILE="defconfig" ;;
    esac
  fi

  log "Kernel: $KERNEL_TYPE, compile: $KERNEL_COMPILE"
}

config_binhost() {
  if [[ $(yesno_dialog "Binary Packages" "Use binary packages (binhost) for faster installation?") == "yes" ]]; then
    USE_BINHOST=1
    log "Binary packages: enabled"
  else
    USE_BINHOST=0
    log "Binary packages: disabled (source compilation only)"
  fi
}

config_package_policy() {
  local choice
  choice=$(menu_dialog "Package Policy" 15 60 \
    "1" "Stable (standard, conservative)" \
    "2" "Testing (~amd64, bleeding-edge)")

  case "$choice" in
    1) PACKAGE_POLICY="stable" ;;
    2) PACKAGE_POLICY="testing" ;;
    *) PACKAGE_POLICY="stable" ;;
  esac

  log "Package policy: $PACKAGE_POLICY"
}

config_filesystem() {
  local choice
  choice=$(menu_dialog "Filesystem" 15 60 \
    "1" "ext4 (stable, widely supported)" \
    "2" "btrfs (modern, with subvolumes)" \
    "3" "xfs (high-performance, large files)")

  case "$choice" in
    1) FS_TYPE="ext4" ;;
    2) FS_TYPE="btrfs" ;;
    3) FS_TYPE="xfs" ;;
    *) FS_TYPE="ext4" ;;
  esac

  log "Filesystem: $FS_TYPE"
}

config_disk() {
  local selected_disk
  local disk_valid=0

  while ((! disk_valid)); do
    msgbox "Disk Selection" "Available disks will be shown. Please select one."

    printf '\nAvailable disks:\n'
    lsblk -dno NAME,SIZE,TYPE,MODEL | awk '$3=="disk" {printf "  /dev/%-12s %-8s %s\n", $1, $2, substr($0, index($0,$4))}'

    selected_disk=$(input_dialog "Disk Selection" "Enter target disk (e.g., /dev/sda):" "/dev/")

    [[ -n "$selected_disk" ]] || { msgbox "Input Error" "Disk path cannot be empty"; continue; }
    [[ -b "$selected_disk" ]] || { msgbox "Input Error" "Not a block device: $selected_disk"; continue; }
    [[ "$(lsblk -dno TYPE "$selected_disk" 2>/dev/null)" == "disk" ]] || { msgbox "Input Error" "$selected_disk is not a whole disk"; continue; }

    if findmnt -rn -S "$selected_disk" >/dev/null 2>&1; then
      msgbox "Input Error" "$selected_disk or its partitions are currently mounted"
      continue
    fi

    disk_valid=1
  done

  DISK="$selected_disk"
  DISK_GIB=$(( $(lsblk -bdno SIZE "$DISK") / 1073741824 ))
  ((DISK_GIB >= 24)) || die "$DISK is only ${DISK_GIB}GiB - at least 24GiB required"

  log "Disk: $DISK ($DISK_GIB GiB)"
}

config_root_size() {
  local handle=0
  [[ "$BOOT_TYPE" == "uefi" ]] && handle=1
  local max_root=$((DISK_GIB - handle - 2))

  local root_size
  while true; do
    root_size=$(input_dialog "Root Partition Size" "Enter root size in GiB (min 20, max $max_root):" "30")

    [[ -n "$root_size" ]] || { msgbox "Input Error" "Root size cannot be empty"; continue; }
    [[ "$root_size" =~ ^[0-9]+$ ]] || { msgbox "Input Error" "Please enter a whole number"; continue; }
    ((root_size >= 20)) || { msgbox "Input Error" "Root must be at least 20GiB"; continue; }
    ((root_size <= max_root)) || { msgbox "Input Error" "Root size too large (max: ${max_root}GiB)"; continue; }

    ROOT_GB="$root_size"
    log "Root size: ${ROOT_GB}GiB"
    break
  done
}

config_identity() {
  local hostname_valid=0
  while ((! hostname_valid)); do
    HOSTNAME=$(input_dialog "Hostname" "Enter hostname:" "gentoo")
    [[ -n "$HOSTNAME" ]] || { msgbox "Input Error" "Hostname cannot be empty"; continue; }
    [[ "$HOSTNAME" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] && hostname_valid=1 || msgbox "Input Error" "Invalid hostname (alphanumeric, dots, hyphens only)"
  done

  local username_valid=0
  while ((! username_valid)); do
    USERNAME=$(input_dialog "Username" "Enter username:" "user")
    [[ -n "$USERNAME" ]] || { msgbox "Input Error" "Username cannot be empty"; continue; }
    [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && username_valid=1 || msgbox "Input Error" "Invalid username (lowercase, digits, underscore, dash only)"
  done

  local timezone_valid=0
  while ((! timezone_valid)); do
    TIMEZONE=$(input_dialog "Timezone" "Enter timezone:" "UTC")
    [[ -n "$TIMEZONE" ]] || { msgbox "Input Error" "Timezone cannot be empty"; continue; }
    [[ -e "/usr/share/zoneinfo/$TIMEZONE" ]] && timezone_valid=1 || msgbox "Input Error" "Unknown timezone: $TIMEZONE"
  done

  KEYMAP=$(input_dialog "Keymap" "Enter console keymap:" "us")
  [[ -n "$KEYMAP" ]] || KEYMAP="us"

  log "Hostname: $HOSTNAME, User: $USERNAME, TZ: $TIMEZONE, Keymap: $KEYMAP"
}

config_passwords() {
  # Root password
  printf '\nEnter password for root: '
  read -rs ROOT_PASS; printf '\n'
  ((${#ROOT_PASS} >= 8)) || die "Root password must be at least 8 characters"

  # User password
  printf 'Enter password for %s: ' "$USERNAME"
  read -rs USER_PASS; printf '\n'
  ((${#USER_PASS} >= 8)) || die "User password must be at least 8 characters"

  log "Passwords configured"
}

config_boot_type() {
  if [[ -d /sys/firmware/efi ]]; then
    BOOT_TYPE="uefi"
  else
    BOOT_TYPE="bios"
  fi

  if [[ $(yesno_dialog "Boot Type" "Use $BOOT_TYPE boot (auto-detected)?") == "yes" ]]; then
    log "Boot type: $BOOT_TYPE"
  else
    if [[ "$BOOT_TYPE" == "uefi" ]]; then
      BOOT_TYPE="bios"
    else
      BOOT_TYPE="uefi"
    fi
    warn "Overriding boot type to: $BOOT_TYPE"
    log "Boot type: $BOOT_TYPE (manual override)"
  fi
}

interactive_config() {
  step "Interactive Configuration"

  config_boot_type
  config_init_system
  config_desktop
  config_kernel
  config_binhost
  config_package_policy
  config_filesystem
  config_disk
  config_root_size
  config_identity
  config_passwords

  show_summary
}

show_summary() {
  step "Configuration Summary"

  # Validate all required variables are set
  local errors=0
  [[ -n "$HOSTNAME" ]] || { warn "Hostname not set"; ((errors++)); }
  [[ -n "$USERNAME" ]] || { warn "Username not set"; ((errors++)); }
  [[ -n "$TIMEZONE" ]] || { warn "Timezone not set"; ((errors++)); }
  [[ -n "$DISK" ]] || { warn "Disk not set"; ((errors++)); }
  [[ -n "$KEYMAP" ]] || { warn "Keymap not set"; ((errors++)); }

  if ((errors > 0)); then
    die "Configuration incomplete: $errors error(s). Please run installer again."
  fi

  printf '  Boot type       : %s\n' "$BOOT_TYPE"
  printf '  Init system     : %s\n' "$INIT_SYSTEM"
  printf '  Desktop         : %s (%s)\n' "$DESKTOP_PROFILE" "$DISPLAY_PROTOCOL"
  printf '  Kernel          : %s (compile: %s)\n' "$KERNEL_TYPE" "$KERNEL_COMPILE"
  printf '  Binary packages : %s\n' "$([[ $USE_BINHOST -eq 1 ]] && echo 'yes' || echo 'no')"
  printf '  Package policy  : %s\n' "$PACKAGE_POLICY"
  printf '  Filesystem      : %s\n' "$FS_TYPE"
  printf '  Disk            : %s (%s GiB - WILL BE ERASED)\n' "$DISK" "$DISK_GIB"
  printf '  Root size       : %s GiB\n' "$ROOT_GB"
  printf '  Hostname/User   : %s / %s\n' "$HOSTNAME" "$USERNAME"
  printf '  Timezone/Keymap : %s / %s\n' "$TIMEZONE" "$KEYMAP"
  printf '\n'

  if [[ $(yesno_dialog "Confirmation" "Proceed with installation? Type YES to confirm") == "yes" ]]; then
    log "Installation confirmed by user"
  else
    die "Installation cancelled by user"
  fi
}

# =============================================================================
# Partitioning
# =============================================================================
reread_partitions() {
  partprobe "$DISK" >/dev/null 2>&1 || blockdev --rereadpt "$DISK" >/dev/null 2>&1 || true
  sleep 1
  local p ok
  for p in "$@"; do
    ok=0
    for _ in $(seq 1 20); do
      if [[ -b "$p" ]]; then ok=1; break; fi
      sleep 0.5
    done
    ((ok)) || die "partition device $p did not appear"
  done
}

partition_disk() {
  step "Partitioning $DISK"

  if [[ "$BOOT_TYPE" == "uefi" ]]; then
    parted -s "$DISK" mklabel gpt || die "failed to write GPT"
    parted -s "$DISK" mkpart EFI fat32 1MiB 1025MiB || die "failed to create EFI partition"
    parted -s "$DISK" set 1 esp on || die "failed to set ESP flag"
    local start_root=1025MiB
    local end_root=$((1025 + ROOT_GB * 1024))MiB
    parted -s "$DISK" mkpart ROOT "$FS_TYPE" "$start_root" "$end_root" || die "failed to create root"
    parted -s "$DISK" mkpart SWAP linux-swap "$end_root" 100% || die "failed to create swap"

    if [[ "$DISK" == *nvme* || "$DISK" == *mmcblk* ]]; then
      PEFI="${DISK}p1"; PROOT="${DISK}p2"; PSWAP="${DISK}p3"
    else
      PEFI="${DISK}1"; PROOT="${DISK}2"; PSWAP="${DISK}3"
    fi
    reread_partitions "$PEFI" "$PROOT" "$PSWAP"
  else
    parted -s "$DISK" mklabel msdos || die "failed to write MBR"
    local start_root=1MiB
    local end_root=$((1 + ROOT_GB * 1024))MiB
    parted -s "$DISK" mkpart primary "$FS_TYPE" "$start_root" "$end_root" || die "failed to create root"
    parted -s "$DISK" mkpart primary linux-swap "$end_root" 100% || die "failed to create swap"

    if [[ "$DISK" == *nvme* || "$DISK" == *mmcblk* ]]; then
      PROOT="${DISK}p1"; PSWAP="${DISK}p2"; PEFI=""
    else
      PROOT="${DISK}1"; PSWAP="${DISK}2"; PEFI=""
    fi
    reread_partitions "$PROOT" "$PSWAP"
  fi

  SWAP_MIB=$(( $(lsblk -bdno SIZE "$PSWAP") / 1048576 ))
  ((SWAP_MIB >= 512)) || die "swap partition too small"

  log "Partition layout: root=$PROOT swap=${SWAP_MIB}MiB${PEFI:+ efi=$PEFI}"
  record OK "partitioning" "root=$PROOT swap=${SWAP_MIB}MiB"
}

# =============================================================================
# Filesystem Creation & Mounting
# =============================================================================
create_filesystems() {
  step "Creating Filesystems"

  if [[ -n "$PEFI" ]]; then
    mkfs.vfat -F 32 -n EFI "$PEFI" >/dev/null || die "failed to format EFI"
    log "formatted EFI partition"
  fi

  case "$FS_TYPE" in
    ext4)
      mkfs.ext4 -F -L root "$PROOT" >/dev/null || die "failed to format root"
      ;;
    btrfs)
      mkfs.btrfs -f -L root "$PROOT" >/dev/null || die "failed to format root"
      ;;
    xfs)
      mkfs.xfs -f -L root "$PROOT" >/dev/null || die "failed to format root"
      ;;
  esac

  mkswap -L swap "$PSWAP" >/dev/null || die "failed to create swap"
  log "formatted root and swap"
  record OK "filesystem creation" "$FS_TYPE root + swap"
}

mount_filesystems() {
  step "Mounting Filesystems"

  [[ -d "$MNT" ]] || mkdir -p "$MNT"
  mount "$PROOT" "$MNT" || die "failed to mount root"

  if [[ -n "$PEFI" ]]; then
    mkdir -p "$MNT/boot/efi"
    mount "$PEFI" "$MNT/boot/efi" || die "failed to mount EFI"
  fi

  swapon "$PSWAP" || die "failed to enable swap"

  MOUNTS_ACTIVE=1
  log "filesystems mounted"
  record OK "mount" "root and boot"
}

# =============================================================================
# Stage3 Download & Extraction
# =============================================================================
download_stage3() {
  step "Downloading Stage3"

  local stage3_base="https://distfiles.gentoo.org/releases/amd64/autobuilds"
  local latest_json="$stage3_base/latest-stage3-amd64-openrc.json"

  if [[ "$INIT_SYSTEM" == "systemd" ]]; then
    latest_json="$stage3_base/latest-stage3-amd64-systemd.json"
  fi

  log "Fetching latest stage3 metadata..."
  local json
  json=$(curl -s "$latest_json") || die "failed to fetch latest stage3"

  local filename
  # Try multiple parsing methods for robustness
  filename=$(printf '%s' "$json" | grep -oP '"uri":\s*"[^"]*"' 2>/dev/null | head -1 | cut -d'"' -f4 | xargs basename 2>/dev/null)

  if [[ -z "$filename" ]]; then
    # Fallback method if grep -oP not available
    filename=$(printf '%s' "$json" | grep '"uri"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/' | xargs basename 2>/dev/null)
  fi

  [[ -n "$filename" ]] || die "failed to parse stage3 filename from: $latest_json"

  local stage3_url="$stage3_base/$filename"
  local target="$MNT/stage3.tar.xz"

  log "Downloading: $filename"
  wget -q -O "$target" "$stage3_url" || die "failed to download stage3 from $stage3_url"

  log "Extracting stage3..."
  tar -xpf "$target" -C "$MNT" || die "failed to extract stage3"

  rm -f "$target"
  log "stage3 installed"
  record OK "stage3" "extracted to $MNT"
}

# =============================================================================
# Chroot & Second Stage Installation (stub)
# =============================================================================
prepare_chroot_script() {
  step "Preparing chroot installation script"

  mkdir -p "$(dirname "$CHROOT_SCRIPT")"

  cat > "$CHROOT_SCRIPT" << 'CHROOT_EOF'
#!/bin/bash
# Second-stage installation script (runs inside chroot)
set -euo pipefail

exec > >(tee -a /install.log) 2>&1

# Will be filled with actual chroot logic
echo "Chroot installation placeholder"
echo "This would configure:"
echo "  - Portage and make.conf"
echo "  - Kernel compilation"
echo "  - Package installation"
echo "  - System configuration"
echo "  - Bootloader"

CHROOT_EOF

  chmod +x "$CHROOT_SCRIPT"
  log "chroot script prepared"
}

# =============================================================================
# Main Installation Flow
# =============================================================================
main() {
  printf '\n' | tee -a "$LIVE_LOG"
  printf '=== Gentoo Interactive Installer ===\n' | tee -a "$LIVE_LOG"
  printf 'Log: %s\n\n' "$LIVE_LOG" | tee -a "$LIVE_LOG"

  setup_tui_backend
  preflight_checks
  hardware_detection
  interactive_config
  partition_disk
  create_filesystems
  mount_filesystems
  download_stage3
  prepare_chroot_script

  print_status_table

  msgbox "Installation Status" "Stage 1 complete. Review log for details."
  log "Installation stage 1 complete"
}

main "$@"
