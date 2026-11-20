#!/usr/bin/env bash
# =============================================================================
# Bootloader Installation Module (runs inside chroot)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

install_bootloader() {
  step "Installing Bootloader"

  load_config

  if [[ "$BOOT_TYPE" == "uefi" ]]; then
    install_grub_uefi
  else
    install_grub_bios
  fi

  success "Bootloader installed"
  record INSTALLED "bootloader" "GRUB"
}

install_grub_uefi() {
  info "Installing GRUB for UEFI..."

  # Install GRUB package
  echo 'GRUB_PLATFORMS="efi-64"' >> /etc/portage/make.conf
  emerge --quiet sys-boot/grub || die "Failed to install GRUB"

  # Install GRUB to EFI
  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo || \
    die "Failed to install GRUB to EFI"

  # Generate GRUB config
  generate_grub_config

  success "GRUB installed for UEFI"
}

install_grub_bios() {
  info "Installing GRUB for BIOS..."

  # Install GRUB package
  emerge --quiet sys-boot/grub || die "Failed to install GRUB"

  # Install GRUB to MBR
  grub-install --target=i386-pc "$DISK" || \
    die "Failed to install GRUB to $DISK"

  # Generate GRUB config
  generate_grub_config

  success "GRUB installed for BIOS"
}

generate_grub_config() {
  info "Generating GRUB configuration..."

  # Configure GRUB
  if [[ -f /etc/default/grub ]]; then
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub
    sed -i 's/^#GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
  fi

  grub-mkconfig -o /boot/grub/grub.cfg || die "Failed to generate GRUB config"

  success "GRUB configuration generated"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_chroot
  install_bootloader
fi
