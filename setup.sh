#!/usr/bin/env bash
# =============================================================================
# Gentoo Linux Installer - Main Setup Script
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/modules/common.sh"

require_root
require_not_chroot

# Initialize logging
INSTALL_LOG="/tmp/gentoo-install-$(date +%Y%m%d-%H%M%S).log"
export INSTALL_LOG

# =============================================================================
# Installation Stages
# =============================================================================

stage1_prepare_disk() {
  step "Stage 1: Disk Preparation"

  source "$SCRIPT_DIR/modules/partition.sh"
  partition_disk

  source "$SCRIPT_DIR/modules/filesystem.sh"
  create_filesystems
  mount_filesystems
}

stage2_install_base() {
  step "Stage 2: Base System Installation"

  source "$SCRIPT_DIR/modules/stage3.sh"
  download_stage3

  source "$SCRIPT_DIR/modules/portage-config.sh"
  configure_portage

  source "$SCRIPT_DIR/modules/chroot-prepare.sh"
  prepare_chroot
}

stage3_configure_chroot() {
  step "Stage 3: Chroot Configuration"

  info "Creating chroot installation script..."

  # Create chroot script that runs all modules inside chroot
  cat > "$CHROOT_SCRIPT" << 'CHROOT_EOF'
#!/bin/bash
set -euo pipefail

# Source common functions
source /tmp/installer-modules/common.sh

# Load configuration
export CONFIG_FILE="/tmp/$(basename "$CONFIG_FILE")"
load_config

# Sync Portage
step "Syncing Portage Repository"
emerge-webrsync || emerge --sync || die "Failed to sync Portage"

# Update Portage
info "Updating Portage..."
emerge --oneshot --quiet portage || warn "Portage update failed"

# Select profile
info "Selecting system profile..."
if [[ "$INIT_SYSTEM" == "systemd" ]]; then
  if [[ "$DESKTOP_PROFILE" != "minimal" ]]; then
    eselect profile set default/linux/amd64/23.0/desktop/systemd
  else
    eselect profile set default/linux/amd64/23.0/systemd
  fi
else
  if [[ "$DESKTOP_PROFILE" != "minimal" ]]; then
    eselect profile set default/linux/amd64/23.0/desktop
  else
    eselect profile set default/linux/amd64/23.0
  fi
fi

# Run configuration modules
source /tmp/installer-modules/system-config.sh
configure_system

source /tmp/installer-modules/kernel-install.sh
install_kernel

source /tmp/installer-modules/bootloader.sh
install_bootloader

source /tmp/installer-modules/network.sh
configure_network

source /tmp/installer-modules/users.sh
setup_users

source /tmp/installer-modules/desktop-install.sh
install_desktop

# Install essential packages
step "Installing Essential Packages"
emerge --quiet app-editors/nano sys-apps/pciutils sys-apps/usbutils || \
  warn "Some essential packages failed to install"

success "Chroot configuration complete!"
CHROOT_EOF

  chmod +x "$CHROOT_SCRIPT"

  info "Entering chroot environment..."
  chroot "$MNT" /bin/bash "$CHROOT_SCRIPT" || die "Chroot installation failed"

  success "Chroot configuration complete"
}

stage4_finalize() {
  step "Stage 4: Finalization"

  info "Installation complete!"
  info "Log file: $INSTALL_LOG"

  print_status_table

  echo ""
  info "Next steps:"
  echo "  1. Review the installation log: $INSTALL_LOG"
  echo "  2. Unmount partitions: umount -R $MNT"
  echo "  3. Reboot: reboot"
  echo ""
  warn "Remember to remove installation media before rebooting!"
}

# =============================================================================
# Main Installation Flow
# =============================================================================

main() {
  clear
  echo "╔════════════════════════════════════════╗"
  echo "║   Gentoo Linux Installer               ║"
  echo "║   Starting Installation...             ║"
  echo "╚════════════════════════════════════════╝"
  echo ""

  # Check for configuration
  if [[ ! -f "$CONFIG_FILE" ]]; then
    die "Configuration not found. Run './configure.sh' first"
  fi

  # Load configuration
  load_config

  info "Installation log: $INSTALL_LOG"
  log "Installation started at $(date)"

  # Run installation stages
  stage1_prepare_disk
  stage2_install_base
  stage3_configure_chroot
  stage4_finalize

  success "Installation completed successfully!"
}

main "$@"
