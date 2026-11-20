#!/usr/bin/env bash
# =============================================================================
# Desktop Environment / Window Manager Installation Module (runs inside chroot)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

install_desktop() {
  step "Installing Desktop Environment"

  load_config

  case "$DESKTOP_PROFILE" in
    minimal)
      info "Minimal install - no desktop environment"
      record NA "desktop" "minimal (no DE/WM)"
      ;;
    kde)
      install_kde_plasma
      ;;
    hyprland)
      install_hyprland
      ;;
    niri)
      install_niri
      ;;
    *)
      warn "Unknown desktop profile: $DESKTOP_PROFILE"
      record NA "desktop" "unknown profile"
      ;;
  esac

  success "Desktop installation complete"
}

install_kde_plasma() {
  info "Installing KDE Plasma..."

  # Install Plasma
  emerge --quiet kde-plasma/plasma-meta || die "Failed to install KDE Plasma"

  # Install KDE applications
  emerge --quiet kde-apps/kde-apps-meta || warn "Failed to install KDE apps"

  # Install SDDM
  emerge --quiet x11-misc/sddm || warn "Failed to install SDDM"

  # Enable SDDM
  if [[ "$INIT_SYSTEM" == "openrc" ]]; then
    rc-update add display-manager default || warn "Failed to enable display-manager"
    sed -i 's/^DISPLAYMANAGER=.*/DISPLAYMANAGER="sddm"/' /etc/conf.d/display-manager
  else
    systemctl enable sddm || warn "Failed to enable SDDM"
  fi

  record INSTALLED "desktop" "KDE Plasma with SDDM"
}

install_hyprland() {
  info "Installing Hyprland..."

  # Unmask Hyprland
  echo "gui-wm/hyprland ~amd64" >> /etc/portage/package.accept_keywords/hyprland

  # Install Hyprland and dependencies
  emerge --quiet gui-wm/hyprland || die "Failed to install Hyprland"
  emerge --quiet gui-apps/waybar gui-apps/wofi x11-terms/kitty || \
    warn "Failed to install Hyprland utilities"

  record INSTALLED "desktop" "Hyprland (Wayland)"
}

install_niri() {
  info "Installing Niri..."

  # Add Niri overlay or unmask
  echo "gui-wm/niri ~amd64" >> /etc/portage/package.accept_keywords/niri

  # Install Niri
  emerge --quiet gui-wm/niri || die "Failed to install Niri"
  emerge --quiet gui-apps/waybar x11-terms/kitty || \
    warn "Failed to install Niri utilities"

  record INSTALLED "desktop" "Niri (Wayland)"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_chroot
  install_desktop
fi
