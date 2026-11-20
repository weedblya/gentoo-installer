#!/usr/bin/env bash
# =============================================================================
# User Management Module (runs inside chroot)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

setup_users() {
  step "Setting Up Users"

  load_config

  # Set root password
  set_root_password

  # Create user if specified
  if [[ -n "$USERNAME" ]]; then
    create_user
  fi

  success "Users configured"
}

set_root_password() {
  info "Setting root password..."

  if [[ -n "$ROOT_PASS" ]]; then
    echo "root:$ROOT_PASS" | chpasswd || die "Failed to set root password"
    success "Root password set"
  else
    warn "No root password set - you will need to set it manually"
  fi

  record OK "root password" "configured"
}

create_user() {
  info "Creating user: $USERNAME"

  # Install sudo
  emerge --quiet app-admin/sudo || warn "Failed to install sudo"

  # Create user with home directory
  useradd -m -G wheel,audio,video,usb,input,portage -s /bin/bash "$USERNAME" || \
    die "Failed to create user $USERNAME"

  # Set user password
  if [[ -n "$USER_PASS" ]]; then
    echo "$USERNAME:$USER_PASS" | chpasswd || warn "Failed to set user password"
  fi

  # Configure sudo
  if [[ -f /etc/sudoers ]]; then
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers || \
      warn "Failed to configure sudo for wheel group"
  fi

  success "User $USERNAME created"
  record OK "user creation" "$USERNAME"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_chroot
  setup_users
fi
