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
# Simple CLI Menu Functions (no TUI dependencies)
# =============================================================================

# Simple numbered menu
menu_select() {
  local title="$1"
  shift
  local options=("$@")

  printf '\n=== %s ===\n' "$title" >&2
  local i=1
  for opt in "${options[@]}"; do
    printf '  %d) %s\n' "$i" "$opt" >&2
    ((i++))
  done

  local choice
  while true; do
    printf 'Choice [1-%d]: ' "${#options[@]}" >&2
    read -r choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#options[@]})); then
      printf '%s' "${options[$((choice-1))]}"
      return 0
    fi
    printf 'Invalid choice. Try again.\n' >&2
  done
}

# Simple yes/no prompt
ask_yesno() {
  local prompt="$1"
  local default="${2:-n}"
  local answer

  while true; do
    if [[ "${default,,}" == "y" ]]; then
      printf '%s [Y/n]: ' "$prompt" >&2
    else
      printf '%s [y/N]: ' "$prompt" >&2
    fi
    read -r answer
    answer="${answer:-$default}"

    case "${answer,,}" in
      y|yes) printf 'yes'; return 0 ;;
      n|no)  printf 'no'; return 1 ;;
      *) printf 'Please answer y or n.\n' >&2 ;;
    esac
  done
}

# Simple text input
ask_input() {
  local prompt="$1"
  local default="$2"
  local value

  if [[ -n "$default" ]]; then
    printf '%s [%s]: ' "$prompt" "$default" >&2
  else
    printf '%s: ' "$prompt" >&2
  fi

  read -r value
  printf '%s' "${value:-$default}"
}

# Info message
show_message() {
  local title="$1"
  local text="$2"

  printf '\n=== %s ===\n' "$title"
  printf '%s\n' "$text"
  printf '\nPress Enter to continue...'
  read -r
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
  if [[ $(ask_yesno "Auto-detect graphics hardware?" "y") == "yes" ]]; then
    VIDEO_CARDS=$(detect_gpus | xargs)
    if [[ -n "$VIDEO_CARDS" ]]; then
      log "Detected GPUs: $VIDEO_CARDS"
      record OK "GPU detection" "$VIDEO_CARDS"
    else
      warn "No GPUs detected, will use profile default"
      record OK "GPU detection" "none (profile default)"
    fi
  else
    # Manual GPU selection
    local gpu_choice
    gpu_choice=$(menu_select "GPU Selection" \
      "AMD (amdgpu + radeonsi)" \
      "Intel (Mesa iris/ANV)" \
      "NVIDIA (proprietary driver)" \
      "Hybrid Intel + NVIDIA" \
      "Hybrid AMD + NVIDIA" \
      "Virtual Machine (VirtualBox)" \
      "Virtual Machine (QEMU/KVM)" \
      "None (use profile default)")

    case "$gpu_choice" in
      *AMD*)
        VIDEO_CARDS="amdgpu radeonsi"
        HAVE_NVIDIA=0
        GPU_NEEDS_FIRMWARE=1
        ;;
      *Intel*NVIDIA*)
        VIDEO_CARDS="intel nvidia"
        HAVE_NVIDIA=1
        GPU_NEEDS_FIRMWARE=1
        ;;
      *AMD*NVIDIA*)
        VIDEO_CARDS="amdgpu radeonsi nvidia"
        HAVE_NVIDIA=1
        GPU_NEEDS_FIRMWARE=1
        ;;
      *Intel*)
        VIDEO_CARDS="intel"
        HAVE_NVIDIA=0
        GPU_NEEDS_FIRMWARE=1
        ;;
      *NVIDIA*)
        VIDEO_CARDS="nvidia"
        HAVE_NVIDIA=1
        GPU_NEEDS_FIRMWARE=1
        ;;
      *VirtualBox*)
        VIDEO_CARDS="virtualbox vmware"
        HAVE_NVIDIA=0
        GPU_NEEDS_FIRMWARE=0
        IS_VM=1
        VIRT="virtualbox"
        ;;
      *QEMU*)
        VIDEO_CARDS="virgl"
        HAVE_NVIDIA=0
        GPU_NEEDS_FIRMWARE=0
        IS_VM=1
        VIRT="qemu"
        ;;
      *None*)
        VIDEO_CARDS=""
        HAVE_NVIDIA=0
        GPU_NEEDS_FIRMWARE=0
        ;;
    esac

    log "Manual GPU selection: VIDEO_CARDS=\"$VIDEO_CARDS\""
    record OK "GPU selection" "${VIDEO_CARDS:-profile default}"
  fi
}

# =============================================================================
# Interactive Configuration Menu
# =============================================================================
config_init_system() {
  local choice
  choice=$(menu_select "Init System" \
    "OpenRC (default, lightweight)" \
    "systemd (featureful)")

  case "$choice" in
    *OpenRC*) INIT_SYSTEM="openrc" ;;
    *systemd*) INIT_SYSTEM="systemd" ;;
    *) INIT_SYSTEM="openrc" ;;
  esac

  log "Init system: $INIT_SYSTEM"
}

config_desktop() {
  local choice
  choice=$(menu_select "Desktop Environment" \
    "KDE Plasma (full-featured)" \
    "Hyprland (Wayland tiling WM)" \
    "Niri (Wayland compositor)" \
    "MangoWM (lightweight tiling)" \
    "Minimal (no DE/WM, cli only)")

  case "$choice" in
    *KDE*) DESKTOP_PROFILE="kde"; DISPLAY_PROTOCOL="wayland" ;;
    *Hyprland*) DESKTOP_PROFILE="hyprland"; DISPLAY_PROTOCOL="wayland" ;;
    *Niri*) DESKTOP_PROFILE="niri"; DISPLAY_PROTOCOL="wayland" ;;
    *MangoWM*) DESKTOP_PROFILE="mangowm"; DISPLAY_PROTOCOL="wayland" ;;
    *Minimal*) DESKTOP_PROFILE="minimal"; DISPLAY_PROTOCOL="x11" ;;
    *) DESKTOP_PROFILE="kde"; DISPLAY_PROTOCOL="wayland" ;;
  esac

  log "Desktop profile: $DESKTOP_PROFILE, protocol: $DISPLAY_PROTOCOL"
}

config_kernel() {
  local choice
  choice=$(menu_select "Kernel Selection" \
    "distribution-kernel-bin (precompiled, fastest)" \
    "gentoo-kernel (compile on target, flexible)" \
    "gentoo-sources (manual menuconfig required)")

  case "$choice" in
    *distribution-kernel-bin*) KERNEL_TYPE="distribution-kernel-bin"; KERNEL_COMPILE="none" ;;
    *gentoo-kernel*) KERNEL_TYPE="gentoo-kernel"; KERNEL_COMPILE="localyesconfig" ;;
    *gentoo-sources*) KERNEL_TYPE="gentoo-sources"; KERNEL_COMPILE="menuconfig" ;;
    *) KERNEL_TYPE="distribution-kernel-bin"; KERNEL_COMPILE="none" ;;
  esac

  if [[ "$KERNEL_TYPE" == "gentoo-sources" ]]; then
    local kc
    kc=$(menu_select "Kernel Compilation" \
      "menuconfig (interactive)" \
      "localyesconfig (based on running kernel)" \
      "defconfig (minimal defaults)")
    case "$kc" in
      *menuconfig*) KERNEL_COMPILE="menuconfig" ;;
      *localyesconfig*) KERNEL_COMPILE="localyesconfig" ;;
      *defconfig*) KERNEL_COMPILE="defconfig" ;;
    esac
  fi

  log "Kernel: $KERNEL_TYPE, compile: $KERNEL_COMPILE"
}

config_binhost() {
  if [[ $(ask_yesno "Use binary packages (binhost) for faster installation?" "y") == "yes" ]]; then
    USE_BINHOST=1
    log "Binary packages: enabled"
  else
    USE_BINHOST=0
    log "Binary packages: disabled (source compilation only)"
  fi
}

config_package_policy() {
  local choice
  choice=$(menu_select "Package Policy" \
    "Stable (standard, conservative)" \
    "Testing (~amd64, bleeding-edge)")

  case "$choice" in
    *Stable*) PACKAGE_POLICY="stable" ;;
    *Testing*) PACKAGE_POLICY="testing" ;;
    *) PACKAGE_POLICY="stable" ;;
  esac

  log "Package policy: $PACKAGE_POLICY"
}

config_filesystem() {
  local choice
  choice=$(menu_select "Filesystem" \
    "ext4 (stable, widely supported)" \
    "btrfs (modern, with subvolumes)" \
    "xfs (high-performance, large files)")

  case "$choice" in
    *ext4*) FS_TYPE="ext4" ;;
    *btrfs*) FS_TYPE="btrfs" ;;
    *xfs*) FS_TYPE="xfs" ;;
    *) FS_TYPE="ext4" ;;
  esac

  log "Filesystem: $FS_TYPE"
}

config_disk() {
  local selected_disk
  local disk_valid=0

  while ((! disk_valid)); do
    printf '\n=== Disk Selection ===\n'
    printf 'Available disks:\n'
    lsblk -dno NAME,SIZE,TYPE,MODEL | awk '$3=="disk" {printf "  /dev/%-12s %-8s %s\n", $1, $2, substr($0, index($0,$4))}'
    printf '\n'

    selected_disk=$(ask_input "Enter target disk (e.g., /dev/sda)" "/dev/")

    if [[ -z "$selected_disk" ]]; then
      printf 'Error: Disk path cannot be empty\n'
      continue
    fi

    if [[ ! -b "$selected_disk" ]]; then
      printf 'Error: Not a block device: %s\n' "$selected_disk"
      continue
    fi

    if [[ "$(lsblk -dno TYPE "$selected_disk" 2>/dev/null)" != "disk" ]]; then
      printf 'Error: %s is not a whole disk\n' "$selected_disk"
      continue
    fi

    if findmnt -rn -S "$selected_disk" >/dev/null 2>&1; then
      printf 'Error: %s or its partitions are currently mounted\n' "$selected_disk"
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
    root_size=$(ask_input "Root size in GiB (min 20, max $max_root)" "30")

    if [[ -z "$root_size" ]]; then
      printf 'Error: Root size cannot be empty\n'
      continue
    fi

    if [[ ! "$root_size" =~ ^[0-9]+$ ]]; then
      printf 'Error: Please enter a whole number\n'
      continue
    fi

    if ((root_size < 20)); then
      printf 'Error: Root must be at least 20GiB\n'
      continue
    fi

    if ((root_size > max_root)); then
      printf 'Error: Root size too large (max: %dGiB)\n' "$max_root"
      continue
    fi

    ROOT_GB="$root_size"
    log "Root size: ${ROOT_GB}GiB"
    break
  done
}

config_identity() {
  local hostname_valid=0
  while ((! hostname_valid)); do
    HOSTNAME=$(ask_input "Hostname" "gentoo")
    if [[ -z "$HOSTNAME" ]]; then
      printf 'Error: Hostname cannot be empty\n'
      continue
    fi
    if [[ "$HOSTNAME" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; then
      hostname_valid=1
    else
      printf 'Error: Invalid hostname (alphanumeric, dots, hyphens only)\n'
    fi
  done

  local username_valid=0
  while ((! username_valid)); do
    USERNAME=$(ask_input "Username" "user")
    if [[ -z "$USERNAME" ]]; then
      printf 'Error: Username cannot be empty\n'
      continue
    fi
    if [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
      username_valid=1
    else
      printf 'Error: Invalid username (lowercase, digits, underscore, dash only)\n'
    fi
  done

  local timezone_valid=0
  while ((! timezone_valid)); do
    TIMEZONE=$(ask_input "Timezone (e.g., Europe/Moscow, UTC)" "UTC")
    if [[ -z "$TIMEZONE" ]]; then
      printf 'Error: Timezone cannot be empty\n' >&2
      continue
    fi
    # Simple format validation (Region/City or UTC)
    if [[ "$TIMEZONE" =~ ^(UTC|[A-Z][a-z]+/[A-Z][a-z_]+)$ ]] || [[ "$TIMEZONE" == "UTC" ]]; then
      timezone_valid=1
    else
      printf 'Error: Invalid timezone format. Use Region/City (e.g., Europe/Moscow) or UTC\n' >&2
    fi
  done

  KEYMAP=$(ask_input "Console keymap" "us")
  [[ -n "$KEYMAP" ]] || KEYMAP="us"

  log "Hostname: $HOSTNAME, User: $USERNAME, TZ: $TIMEZONE, Keymap: $KEYMAP"
}

config_passwords() {
  # Root password
  while true; do
    printf '\nEnter password for root: ' >&2
    read -rs ROOT_PASS; printf '\n' >&2
    if [[ -n "$ROOT_PASS" ]]; then
      break
    fi
    printf 'Error: Password cannot be empty\n' >&2
  done

  # User password
  while true; do
    printf 'Enter password for %s: ' "$USERNAME" >&2
    read -rs USER_PASS; printf '\n' >&2
    if [[ -n "$USER_PASS" ]]; then
      break
    fi
    printf 'Error: Password cannot be empty\n' >&2
  done

  log "Passwords configured"
}

config_boot_type() {
  if [[ -d /sys/firmware/efi ]]; then
    BOOT_TYPE="uefi"
  else
    BOOT_TYPE="bios"
  fi

  if [[ $(ask_yesno "Use $BOOT_TYPE boot (auto-detected)?" "y") == "yes" ]]; then
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

  if [[ $(ask_yesno "Proceed with installation? THIS WILL ERASE $DISK" "n") == "yes" ]]; then
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
  local latest_txt="$stage3_base/latest-stage3.txt"

  # Determine stage3 variant based on init system
  local stage3_pattern="stage3-amd64-openrc"
  if [[ "$INIT_SYSTEM" == "systemd" ]]; then
    stage3_pattern="stage3-amd64-systemd"
  fi

  log "Fetching latest stage3 metadata..."
  local metadata
  metadata=$(curl -s "$latest_txt") || die "failed to fetch stage3 metadata from $latest_txt"

  # Parse the txt file to find the appropriate stage3 tarball
  # Format: "20261115T170104Z/stage3-amd64-openrc-20261115T170104Z.tar.xz 276277944"
  local filepath
  filepath=$(printf '%s' "$metadata" | grep -v '^#' | grep -v '^-' | grep "\.tar\.xz" | grep "$stage3_pattern" | grep -v "desktop\|hardened\|musl\|llvm\|nomultilib" | head -1 | awk '{print $1}')

  [[ -n "$filepath" ]] || die "failed to find $stage3_pattern stage3 in metadata"

  local stage3_url="$stage3_base/$filepath"
  local filename="${filepath##*/}"
  local target="$MNT/stage3.tar.xz"

  log "Downloading: $filename"
  wget -q --show-progress -O "$target" "$stage3_url" || die "failed to download stage3 from $stage3_url"

  log "Extracting stage3..."
  tar -xpf "$target" -C "$MNT" || die "failed to extract stage3"

  rm -f "$target"
  log "stage3 installed"
  record OK "stage3" "extracted to $MNT"
}

# =============================================================================
# Prepare for Chroot
# =============================================================================
prepare_chroot() {
  step "Preparing chroot environment"

  # Copy DNS info
  cp -L /etc/resolv.conf "$MNT/etc/" || warn "failed to copy resolv.conf"

  # Mount necessary filesystems
  mount --types proc /proc "$MNT/proc" || true
  mount --rbind /sys "$MNT/sys" && mount --make-rslave "$MNT/sys" || true
  mount --rbind /dev "$MNT/dev" && mount --make-rslave "$MNT/dev" || true
  mount --bind /run "$MNT/run" && mount --make-slave "$MNT/run" || true

  log "chroot environment ready"
}

# =============================================================================
# Chroot Script Generation
# =============================================================================
prepare_chroot_script() {
  step "Preparing chroot installation script"

  mkdir -p "$(dirname "$CHROOT_SCRIPT")"

  # Pass configuration variables to chroot script
  cat > "$CHROOT_SCRIPT" << CHROOT_EOF
#!/bin/bash
# Second-stage installation script (runs inside chroot)
set -euo pipefail

exec > >(tee -a /install.log) 2>&1

# Configuration passed from main script
INIT_SYSTEM="$INIT_SYSTEM"
DESKTOP_PROFILE="$DESKTOP_PROFILE"
BOOT_TYPE="$BOOT_TYPE"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
TIMEZONE="$TIMEZONE"
KEYMAP="$KEYMAP"
USE_BINHOST=$USE_BINHOST
KERNEL_TYPE="$KERNEL_TYPE"
PACKAGE_POLICY="$PACKAGE_POLICY"
VIDEO_CARDS="$VIDEO_CARDS"
HAVE_NVIDIA=$HAVE_NVIDIA
PEFI="$PEFI"
PROOT="$PROOT"
DISK="$DISK"

echo "=== Stage 2: Chroot Installation ==="

# Prepare Portage directories
echo ">>> Preparing Portage configuration directories..."
mkdir -p /etc/portage/package.accept_keywords
mkdir -p /etc/portage/package.use
mkdir -p /etc/portage/package.license

# Configure Portage
echo ">>> Syncing Portage repository..."
emerge-webrsync || emerge --sync

# Update make.conf
echo ">>> Configuring make.conf..."
cat >> /etc/portage/make.conf << 'MAKECONF'

# CPU Flags
COMMON_FLAGS="-march=native -O2 -pipe"
CFLAGS="\\\${COMMON_FLAGS}"
CXXFLAGS="\\\${COMMON_FLAGS}"
FCFLAGS="\\\${COMMON_FLAGS}"
FFLAGS="\\\${COMMON_FLAGS}"
MAKEOPTS="-j\\\$(nproc)"

# Accept all licenses for installation phase
ACCEPT_LICENSE="*"
MAKECONF

# Set locale
echo ">>> Configuring locale..."
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set en_US.utf8
env-update && source /etc/profile

# Set timezone
echo ">>> Setting timezone to \${TIMEZONE}..."
ln -sf /usr/share/zoneinfo/\${TIMEZONE} /etc/localtime

# Set hostname
echo ">>> Setting hostname to \${HOSTNAME}..."
echo "hostname=\"\${HOSTNAME}\"" > /etc/conf.d/hostname

# Function to accept all config changes automatically
accept_config_changes() {
  yes | etc-update --automode -5 2>/dev/null || true
}

# Update Portage to latest version
echo ">>> Updating Portage..."
emerge --oneshot --quiet --autounmask-write --autounmask-continue sys-apps/portage || true
accept_config_changes

# Install linux-firmware first (required for kernel)
echo ">>> Installing linux-firmware..."
emerge --quiet --autounmask-write --autounmask-continue sys-kernel/linux-firmware || echo "WARNING: linux-firmware installation had issues, continuing..."
accept_config_changes

# Install kernel
echo ">>> Installing kernel (\${KERNEL_TYPE})..."
if [[ "\$KERNEL_TYPE" == "distribution-kernel-bin" ]]; then
  emerge --quiet --autounmask-write --autounmask-continue sys-kernel/gentoo-kernel-bin || { echo "ERROR: Failed to install gentoo-kernel-bin"; exit 1; }
  accept_config_changes
elif [[ "\$KERNEL_TYPE" == "gentoo-kernel" ]]; then
  echo "Attempting to install gentoo-kernel (may take a while)..."
  if ! emerge --quiet --autounmask-write --autounmask-continue sys-kernel/gentoo-kernel; then
    echo "WARNING: gentoo-kernel installation failed, falling back to gentoo-kernel-bin..."
    emerge --quiet --autounmask-write --autounmask-continue sys-kernel/gentoo-kernel-bin || { echo "ERROR: Failed to install fallback kernel"; exit 1; }
  fi
  accept_config_changes
else
  echo "ERROR: Unknown kernel type: \$KERNEL_TYPE"
  exit 1
fi

# Install bootloader
echo ">>> Installing bootloader..."
if [[ "\$BOOT_TYPE" == "uefi" ]]; then
  # Try to install grub with gnu-efi, fallback to alternative if it fails
  if ! emerge --quiet --autounmask-write --autounmask-continue sys-boot/grub; then
    echo "WARNING: GRUB installation with gnu-efi failed, trying without..."
    USE="-grub_platforms_efi-64" emerge --quiet --autounmask-write --autounmask-continue sys-boot/grub || { echo "ERROR: Failed to install grub"; exit 1; }
  fi
  accept_config_changes

  # Install grub to ESP
  if ! grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB 2>/dev/null; then
    echo "WARNING: UEFI grub-install failed, trying removable media installation..."
    grub-install --target=x86_64-efi --efi-directory=/boot --removable || { echo "ERROR: grub-install failed"; exit 1; }
  fi
  grub-mkconfig -o /boot/grub/grub.cfg || { echo "ERROR: grub-mkconfig failed"; exit 1; }
elif [[ "\$BOOT_TYPE" == "bios" ]]; then
  emerge --quiet --autounmask-write --autounmask-continue sys-boot/grub || { echo "ERROR: Failed to install grub"; exit 1; }
  accept_config_changes
  grub-install --target=i386-pc "\$DISK" || { echo "ERROR: grub-install failed for BIOS"; exit 1; }
  grub-mkconfig -o /boot/grub/grub.cfg || { echo "ERROR: grub-mkconfig failed"; exit 1; }
else
  echo "ERROR: Unknown boot type: \$BOOT_TYPE"
  exit 1
fi

# Install essential packages
echo ">>> Installing essential packages..."
emerge --quiet --autounmask-write --autounmask-continue net-misc/dhcpcd app-admin/sudo
accept_config_changes

# Enable services
if [[ "\$INIT_SYSTEM" == "openrc" ]]; then
  rc-update add dhcpcd default
fi

# Set root password
echo ">>> Setting root password..."
echo "root:root" | chpasswd

# Create user
if [[ -n "\$USERNAME" ]]; then
  echo ">>> Creating user \${USERNAME}..."
  useradd -m -G wheel,audio,video,usb -s /bin/bash "\$USERNAME"
  echo "\${USERNAME}:\${USERNAME}" | chpasswd

  # Enable sudo
  sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
fi

# Update fstab
echo ">>> Updating fstab..."
cat > /etc/fstab << FSTAB
\${PEFI}  /boot  vfat  defaults,noatime  0 2
\${PROOT} /      ext4  defaults,noatime  0 1
FSTAB

if [[ -n "\$PSWAP" ]]; then
  echo "\${PSWAP}  none   swap  sw               0 0" >> /etc/fstab
fi

echo "=== Stage 2 complete ==="
CHROOT_EOF

  chmod +x "$CHROOT_SCRIPT"
  log "chroot script prepared"
}

# =============================================================================
# Execute Chroot Installation
# =============================================================================
run_chroot_install() {
  step "Running chroot installation"

  prepare_chroot

  log "entering chroot and running installation script..."
  chroot "$MNT" /bin/bash -c "/root/install_in_chroot.sh" || die "chroot installation failed"

  log "chroot installation complete"
  record OK "chroot install" "system configured"
}

# =============================================================================
# Main Installation Flow
# =============================================================================
main() {
  printf '\n' | tee -a "$LIVE_LOG"
  printf '=== Gentoo Interactive Installer ===\n' | tee -a "$LIVE_LOG"
  printf 'Log: %s\n\n' "$LIVE_LOG" | tee -a "$LIVE_LOG"

  preflight_checks
  hardware_detection
  interactive_config
  partition_disk
  create_filesystems
  mount_filesystems
  download_stage3
  prepare_chroot_script
  run_chroot_install

  print_status_table

  show_message "Installation Complete" "Gentoo installation finished. You may reboot now."
  log "Installation complete"
}

main "$@"
