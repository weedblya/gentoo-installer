#!/usr/bin/env bash
# =============================================================================
# Network Configuration Module (runs inside chroot)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

configure_network() {
  step "Configuring Network"

  load_config

  # Detect network interface
  local net_iface
  net_iface=$(ip -o link show | awk -F': ' '$2 !~ /^(lo|sit|vir)/ {print $2; exit}')

  if [[ -z "$net_iface" ]]; then
    warn "No network interface detected"
    net_iface="eth0"
  fi

  info "Network interface: $net_iface"

  if [[ "$DESKTOP_PROFILE" == "minimal" ]]; then
    setup_dhcpcd "$net_iface"
  else
    setup_networkmanager
  fi

  success "Network configured"
}

setup_dhcpcd() {
  local iface=$1

  info "Setting up dhcpcd for $iface..."

  emerge --quiet net-misc/dhcpcd || die "Failed to install dhcpcd"

  if [[ "$INIT_SYSTEM" == "openrc" ]]; then
    rc-update add dhcpcd default || warn "Failed to add dhcpcd to default runlevel"
  else
    systemctl enable dhcpcd || warn "Failed to enable dhcpcd service"
  fi

  record INSTALLED "network" "dhcpcd ($iface)"
}

setup_networkmanager() {
  info "Setting up NetworkManager..."

  emerge --quiet net-misc/networkmanager || die "Failed to install NetworkManager"

  if [[ "$INIT_SYSTEM" == "openrc" ]]; then
    rc-update add NetworkManager default || warn "Failed to add NetworkManager to default runlevel"
  else
    systemctl enable NetworkManager || warn "Failed to enable NetworkManager service"
  fi

  record INSTALLED "network" "NetworkManager"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_chroot
  configure_network
fi
