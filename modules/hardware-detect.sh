#!/usr/bin/env bash
# =============================================================================
# Hardware Detection Module
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

detect_hardware() {
  step "Hardware Detection"

  # Detect virtualization
  IS_VM=0
  VIRT="none"
  if command -v systemd-detect-virt &>/dev/null; then
    VIRT=$(systemd-detect-virt 2>/dev/null || echo "none")
    [[ "$VIRT" != "none" ]] && IS_VM=1
  fi

  if ((IS_VM)); then
    info "Virtualization detected: $VIRT"
    record OK "virtualization detection" "$VIRT"
  else
    info "Running on physical hardware"
    record OK "virtualization detection" "none (physical)"
  fi

  # Detect GPU
  detect_gpu

  # Detect boot type
  detect_boot_type

  success "Hardware detection complete"
}

detect_gpu() {
  info "Detecting GPU..."

  VIDEO_CARDS=""
  HAVE_NVIDIA=0
  GPU_NEEDS_FIRMWARE=0

  # Check for NVIDIA
  if lspci | grep -qi nvidia; then
    VIDEO_CARDS="nvidia"
    HAVE_NVIDIA=1
    GPU_NEEDS_FIRMWARE=1
    info "NVIDIA GPU detected"
  fi

  # Check for AMD
  if lspci | grep -Ei 'vga.*amd|vga.*ati|display.*amd|display.*ati'; then
    [[ -n "$VIDEO_CARDS" ]] && VIDEO_CARDS="$VIDEO_CARDS "
    VIDEO_CARDS="${VIDEO_CARDS}radeonsi"
    GPU_NEEDS_FIRMWARE=1
    info "AMD GPU detected"
  fi

  # Check for Intel
  if lspci | grep -Ei 'vga.*intel|display.*intel'; then
    [[ -n "$VIDEO_CARDS" ]] && VIDEO_CARDS="$VIDEO_CARDS "
    VIDEO_CARDS="${VIDEO_CARDS}intel"
    info "Intel GPU detected"
  fi

  # Fallback for VMs
  if [[ -z "$VIDEO_CARDS" ]] && ((IS_VM)); then
    if lspci | grep -qi vmware; then
      VIDEO_CARDS="vmware"
    elif lspci | grep -qi virtio; then
      VIDEO_CARDS="virtio"
    elif lspci | grep -qi qxl; then
      VIDEO_CARDS="qxl"
    else
      VIDEO_CARDS="dummy"
    fi
    info "Virtual GPU detected: $VIDEO_CARDS"
  fi

  [[ -z "$VIDEO_CARDS" ]] && VIDEO_CARDS="dummy"

  record OK "GPU detection" "${VIDEO_CARDS}"
}

detect_boot_type() {
  info "Detecting boot type..."

  if [[ -d /sys/firmware/efi/efivars ]]; then
    BOOT_TYPE="uefi"
    info "UEFI boot detected"
    record OK "boot type" "UEFI"
  else
    BOOT_TYPE="bios"
    info "BIOS boot detected"
    record OK "boot type" "BIOS"
  fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_root
  detect_hardware
fi
