#!/usr/bin/env bash
# =============================================================================
# Chroot Preparation Module
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

prepare_chroot() {
  step "Preparing Chroot Environment"

  load_config

  # Mount necessary filesystems
  mount_virtual_filesystems

  # Copy configuration into chroot
  copy_config_to_chroot

  success "Chroot environment prepared"
  record OK "chroot preparation" "virtual filesystems mounted"
}

mount_virtual_filesystems() {
  info "Mounting virtual filesystems..."

  mount --types proc /proc "$MNT/proc" || die "Failed to mount /proc"
  mount --rbind /sys "$MNT/sys" || die "Failed to mount /sys"
  mount --make-rslave "$MNT/sys" || die "Failed to set /sys as rslave"
  mount --rbind /dev "$MNT/dev" || die "Failed to mount /dev"
  mount --make-rslave "$MNT/dev" || die "Failed to set /dev as rslave"
  mount --bind /run "$MNT/run" || die "Failed to mount /run"
  mount --make-slave "$MNT/run" || die "Failed to set /run as slave"

  # For systems using systemd
  if [[ -L /dev/shm ]]; then
    mkdir -p "$MNT/$(readlink /dev/shm)" || true
  fi

  success "Virtual filesystems mounted"
}

copy_config_to_chroot() {
  info "Copying configuration to chroot..."

  # Copy installer config
  cp "$CONFIG_FILE" "$MNT/tmp/" || warn "Failed to copy config"

  # Copy modules into chroot
  mkdir -p "$MNT/tmp/installer-modules"
  cp -r "$SCRIPT_DIR"/* "$MNT/tmp/installer-modules/" || warn "Failed to copy modules"

  success "Configuration copied to chroot"
}

enter_chroot() {
  info "Entering chroot environment..."
  chroot "$MNT" /bin/bash --login
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_root
  prepare_chroot
fi
