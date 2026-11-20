#!/usr/bin/env bash
# =============================================================================
# Common functions and variables for Gentoo Installer
# =============================================================================

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Constants
readonly MNT="/mnt/gentoo"
readonly CHROOT_SCRIPT="$MNT/root/install_in_chroot.sh"
readonly CONFIG_FILE="/tmp/gentoo-installer-config.env"

# Logging functions
ts() { date '+%H:%M:%S'; }

log() {
  printf '[%s] %s\n' "$(ts)" "$*"
  [[ -n "${INSTALL_LOG:-}" ]] && printf '[%s] %s\n' "$(ts)" "$*" >> "$INSTALL_LOG"
}

info() {
  printf "${CYAN}[INFO]${NC} %s\n" "$*"
  log "INFO: $*"
}

success() {
  printf "${GREEN}[OK]${NC} %s\n" "$*"
  log "SUCCESS: $*"
}

warn() {
  printf "${YELLOW}[WARNING]${NC} %s\n" "$*" >&2
  log "WARNING: $*"
}

error() {
  printf "${RED}[ERROR]${NC} %s\n" "$*" >&2
  log "ERROR: $*"
}

die() {
  error "$*"
  exit 1
}

step() {
  printf '\n${BLUE}=== %s ===${NC}\n' "$*"
  log "STEP: $*"
}

# Check if running as root
require_root() {
  [[ $EUID -eq 0 ]] || die "This script must be run as root"
}

# Check if NOT in chroot
require_not_chroot() {
  if [[ "$(stat -c %d:%i /)" != "$(stat -c %d:%i /proc/1/root/.)" ]]; then
    die "This script should not be run from inside a chroot environment"
  fi
}

# Check if IN chroot
require_chroot() {
  if [[ "$(stat -c %d:%i /)" == "$(stat -c %d:%i /proc/1/root/.)" ]]; then
    die "This script must be run from inside a chroot environment"
  fi
}

# Load configuration
load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    success "Configuration loaded from $CONFIG_FILE"
  else
    die "Configuration file not found: $CONFIG_FILE"
  fi
}

# Save configuration
save_config() {
  cat > "$CONFIG_FILE" << EOF
# Gentoo Installer Configuration
# Generated on $(date)

# System Configuration
HOSTNAME="${HOSTNAME:-gentoo}"
USERNAME="${USERNAME:-}"
TIMEZONE="${TIMEZONE:-UTC}"
KEYMAP="${KEYMAP:-us}"

# Installation Options
INIT_SYSTEM="${INIT_SYSTEM:-openrc}"
DESKTOP_PROFILE="${DESKTOP_PROFILE:-minimal}"
DISPLAY_PROTOCOL="${DISPLAY_PROTOCOL:-wayland}"
BOOT_TYPE="${BOOT_TYPE:-uefi}"
FS_TYPE="${FS_TYPE:-ext4}"

# Disk Configuration
DISK="${DISK:-}"
ROOT_GB="${ROOT_GB:-30}"
PEFI="${PEFI:-}"
PROOT="${PROOT:-}"
PSWAP="${PSWAP:-}"

# Package Options
USE_BINHOST="${USE_BINHOST:-0}"
KERNEL_TYPE="${KERNEL_TYPE:-distribution-kernel-bin}"
PACKAGE_POLICY="${PACKAGE_POLICY:-stable}"
VIDEO_CARDS="${VIDEO_CARDS:-}"
HAVE_NVIDIA="${HAVE_NVIDIA:-0}"

# Passwords (will be set during configuration)
ROOT_PASS="${ROOT_PASS:-}"
USER_PASS="${USER_PASS:-}"
EOF
  success "Configuration saved to $CONFIG_FILE"
}

# Status tracking
STATUS_OK=0
STATUS_INSTALLED=0
STATUS_NA=0
STATUS_FAILED=0
STATUS_LINES=()

record() {
  local status=$1
  local component=$2
  local detail=$3

  case "$status" in
    OK)
      ((STATUS_OK++))
      ;;
    INSTALLED)
      ((STATUS_INSTALLED++))
      ;;
    NA)
      ((STATUS_NA++))
      ;;
    FAILED)
      ((STATUS_FAILED++))
      ;;
  esac

  STATUS_LINES+=("$status|$component|$detail")
}

print_status_table() {
  step "Installation Status"
  printf "%-10s %-30s %-50s\n" "STATUS" "CHECK" "DETAIL"
  printf "%s\n" "$(printf '%.0s-' {1..90})"

  for line in "${STATUS_LINES[@]}"; do
    IFS='|' read -r status component detail <<< "$line"
    printf "%-10s %-30s %-50s\n" "$status" "$component" "$detail"
  done

  printf "\n"
  printf "OK: %d   INSTALLED: %d   N/A: %d   FAILED: %d\n" \
    "$STATUS_OK" "$STATUS_INSTALLED" "$STATUS_NA" "$STATUS_FAILED"
}

# Cleanup function
MOUNTS_ACTIVE=0

cleanup() {
  local rc=$?
  trap - EXIT INT TERM ERR

  if ((MOUNTS_ACTIVE)); then
    warn "Cleaning up mounts..."
    sync || true
    umount -R "$MNT/boot/efi" 2>/dev/null || true
    umount -R "$MNT/boot"     2>/dev/null || true
    umount -R "$MNT/proc"     2>/dev/null || true
    umount -R "$MNT/sys"      2>/dev/null || true
    umount -R "$MNT/dev"      2>/dev/null || true
    umount -R "$MNT/run"      2>/dev/null || true
    umount -R "$MNT"          2>/dev/null || umount -l "$MNT" 2>/dev/null || true
    swapoff "${PSWAP:-}"      2>/dev/null || true
  fi

  [[ $rc -ne 0 ]] && error "Installation failed with exit code $rc"
  exit "$rc"
}

trap cleanup EXIT INT TERM
