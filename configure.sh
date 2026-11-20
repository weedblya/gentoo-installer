#!/usr/bin/env bash
# =============================================================================
# Interactive Configuration Script
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/modules/common.sh"

require_root
require_not_chroot

# =============================================================================
# Interactive Configuration Functions
# =============================================================================

select_disk() {
  step "Disk Selection"

  echo "Available disks:"
  lsblk -d -o NAME,SIZE,TYPE,MODEL | grep disk
  echo ""

  read -p "Enter disk to install to (e.g., /dev/sda): " DISK
  [[ ! -b "$DISK" ]] && die "Invalid disk: $DISK"

  info "Selected disk: $DISK"
}

configure_basic() {
  step "Basic Configuration"

  read -p "Hostname [gentoo]: " HOSTNAME
  HOSTNAME=${HOSTNAME:-gentoo}

  read -p "Username (leave empty for root-only): " USERNAME

  read -p "Timezone [UTC]: " TIMEZONE
  TIMEZONE=${TIMEZONE:-UTC}

  read -p "Keymap [us]: " KEYMAP
  KEYMAP=${KEYMAP:-us}
}

configure_init_system() {
  step "Init System Selection"

  echo "Select init system:"
  echo "1) OpenRC (default)"
  echo "2) systemd"
  read -p "Choice [1]: " init_choice
  init_choice=${init_choice:-1}

  case "$init_choice" in
    1) INIT_SYSTEM="openrc" ;;
    2) INIT_SYSTEM="systemd" ;;
    *) INIT_SYSTEM="openrc" ;;
  esac

  info "Init system: $INIT_SYSTEM"
}

configure_desktop() {
  step "Desktop Environment Selection"

  echo "Select desktop environment:"
  echo "1) Minimal (no DE/WM)"
  echo "2) KDE Plasma"
  echo "3) Hyprland (Wayland)"
  echo "4) Niri (Wayland)"
  read -p "Choice [1]: " desktop_choice
  desktop_choice=${desktop_choice:-1}

  case "$desktop_choice" in
    1)
      DESKTOP_PROFILE="minimal"
      DISPLAY_PROTOCOL="none"
      ;;
    2)
      DESKTOP_PROFILE="kde"
      DISPLAY_PROTOCOL="x11"
      ;;
    3)
      DESKTOP_PROFILE="hyprland"
      DISPLAY_PROTOCOL="wayland"
      ;;
    4)
      DESKTOP_PROFILE="niri"
      DISPLAY_PROTOCOL="wayland"
      ;;
    *)
      DESKTOP_PROFILE="minimal"
      DISPLAY_PROTOCOL="none"
      ;;
  esac

  info "Desktop: $DESKTOP_PROFILE ($DISPLAY_PROTOCOL)"
}

configure_filesystem() {
  step "Filesystem Configuration"

  echo "Select filesystem type:"
  echo "1) ext4 (default)"
  echo "2) xfs"
  echo "3) btrfs"
  read -p "Choice [1]: " fs_choice
  fs_choice=${fs_choice:-1}

  case "$fs_choice" in
    1) FS_TYPE="ext4" ;;
    2) FS_TYPE="xfs" ;;
    3) FS_TYPE="btrfs" ;;
    *) FS_TYPE="ext4" ;;
  esac

  read -p "Root partition size in GB [30]: " ROOT_GB
  ROOT_GB=${ROOT_GB:-30}

  info "Filesystem: $FS_TYPE, Root size: ${ROOT_GB}GB"
}

configure_kernel() {
  step "Kernel Selection"

  echo "Select kernel type:"
  echo "1) distribution-kernel-bin (binary, fastest)"
  echo "2) gentoo-kernel-bin (binary)"
  echo "3) gentoo-kernel (compile from source, slow)"
  read -p "Choice [1]: " kernel_choice
  kernel_choice=${kernel_choice:-1}

  case "$kernel_choice" in
    1) KERNEL_TYPE="distribution-kernel-bin" ;;
    2) KERNEL_TYPE="gentoo-kernel-bin" ;;
    3) KERNEL_TYPE="gentoo-kernel" ;;
    *) KERNEL_TYPE="distribution-kernel-bin" ;;
  esac

  info "Kernel: $KERNEL_TYPE"
}

configure_packages() {
  step "Package Configuration"

  echo "Select package policy:"
  echo "1) stable (recommended)"
  echo "2) testing (~amd64)"
  read -p "Choice [1]: " pkg_choice
  pkg_choice=${pkg_choice:-1}

  case "$pkg_choice" in
    1) PACKAGE_POLICY="stable" ;;
    2) PACKAGE_POLICY="testing" ;;
    *) PACKAGE_POLICY="stable" ;;
  esac

  read -p "Use binary packages from Gentoo mirrors? (y/n) [n]: " use_bin
  if [[ "$use_bin" == "y" ]] || [[ "$use_bin" == "Y" ]]; then
    USE_BINHOST=1
  else
    USE_BINHOST=0
  fi

  info "Package policy: $PACKAGE_POLICY, Binary host: $USE_BINHOST"
}

configure_passwords() {
  step "Password Configuration"

  # Root password
  while true; do
    read -s -p "Root password: " ROOT_PASS
    echo ""
    read -s -p "Confirm root password: " ROOT_PASS_CONFIRM
    echo ""

    if [[ "$ROOT_PASS" == "$ROOT_PASS_CONFIRM" ]]; then
      break
    else
      error "Passwords do not match, try again"
    fi
  done

  # User password (if user was specified)
  if [[ -n "$USERNAME" ]]; then
    while true; do
      read -s -p "Password for $USERNAME: " USER_PASS
      echo ""
      read -s -p "Confirm password: " USER_PASS_CONFIRM
      echo ""

      if [[ "$USER_PASS" == "$USER_PASS_CONFIRM" ]]; then
        break
      else
        error "Passwords do not match, try again"
      fi
    done
  fi
}

show_configuration_summary() {
  step "Configuration Summary"

  cat << EOF

Hostname:         $HOSTNAME
Username:         ${USERNAME:-<none>}
Timezone:         $TIMEZONE
Keymap:           $KEYMAP
Init System:      $INIT_SYSTEM
Desktop:          $DESKTOP_PROFILE ($DISPLAY_PROTOCOL)
Disk:             $DISK
Filesystem:       $FS_TYPE
Root Size:        ${ROOT_GB}GB
Kernel:           $KERNEL_TYPE
Package Policy:   $PACKAGE_POLICY
Binary Packages:  $(( USE_BINHOST ? "Yes" : "No" ))

EOF

  read -p "Proceed with installation? (yes/no): " confirm
  [[ "$confirm" != "yes" ]] && die "Installation cancelled"
}

# =============================================================================
# Main Configuration Flow
# =============================================================================

main() {
  clear
  echo "╔════════════════════════════════════════╗"
  echo "║   Gentoo Linux Interactive Installer   ║"
  echo "║           Configuration Setup          ║"
  echo "╚════════════════════════════════════════╝"
  echo ""

  # Run hardware detection
  source "$SCRIPT_DIR/modules/hardware-detect.sh"
  detect_hardware

  # Interactive configuration
  select_disk
  configure_basic
  configure_init_system
  configure_desktop
  configure_filesystem
  configure_kernel
  configure_packages
  configure_passwords

  # Show summary
  show_configuration_summary

  # Save configuration
  save_config

  success "Configuration saved!"
  info "Run './setup.sh' to start the installation"
}

main "$@"
