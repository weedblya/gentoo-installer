#!/usr/bin/env bash
# =============================================================================
# Kernel Installation Module (runs inside chroot)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

install_kernel() {
  step "Installing Kernel"

  load_config

  # Install linux-firmware first if needed
  if [[ "$GPU_NEEDS_FIRMWARE" == "1" ]] || ! ((IS_VM)); then
    info "Installing linux-firmware..."
    emerge --quiet sys-kernel/linux-firmware || warn "Failed to install linux-firmware"
  fi

  # Install installkernel and dracut
  info "Installing kernel infrastructure..."
  emerge --quiet sys-kernel/installkernel || die "Failed to install installkernel"

  # Install dracut separately with error handling
  info "Installing dracut..."
  USE="-systemd" emerge --quiet sys-kernel/dracut || {
    warn "Failed to install dracut, continuing anyway..."
  }

  # Install the kernel
  install_kernel_package

  success "Kernel installed"
  record INSTALLED "kernel" "$KERNEL_TYPE"
}

install_kernel_package() {
  local kernel_pkg="$KERNEL_TYPE"

  info "Installing kernel: $kernel_pkg"
  info "This may take a while..."

  # Log kernel installation
  local kernel_log="/tmp/kernel-install.log"

  if [[ "$kernel_pkg" == "gentoo-kernel" ]]; then
    warn "Compiling kernel from source (20-60 minutes depending on CPU)..."

    if ! emerge --quiet sys-kernel/gentoo-kernel &>"$kernel_log"; then
      error "Failed to install gentoo-kernel"
      warn "This can happen in live environment due to 'Unable to calculate Linux Kernel version'"
      warn "Falling back to binary kernel (gentoo-kernel-bin)..."

      kernel_pkg="gentoo-kernel-bin"
    fi
  fi

  # Install binary kernel (either as fallback or as selected option)
  if [[ "$kernel_pkg" == "gentoo-kernel-bin" ]] || [[ "$kernel_pkg" == "distribution-kernel-bin" ]]; then
    info "Installing binary kernel..."
    emerge --quiet sys-kernel/gentoo-kernel-bin || \
      emerge --quiet sys-kernel/distribution-kernel-bin || \
      die "Failed to install binary kernel"
  fi

  # Verify kernel was installed
  if ! ls /boot/vmlinuz-* &>/dev/null; then
    die "Kernel installation failed - no vmlinuz found in /boot"
  fi

  success "Kernel package installed: $kernel_pkg"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_chroot
  install_kernel
fi
