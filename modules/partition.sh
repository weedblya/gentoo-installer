#!/usr/bin/env bash
# =============================================================================
# Disk Partitioning Module
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

partition_disk() {
  step "Disk Partitioning"

  load_config

  [[ -z "$DISK" ]] && die "DISK variable not set"
  [[ ! -b "$DISK" ]] && die "Disk not found: $DISK"

  info "Partitioning disk: $DISK"
  info "Boot type: $BOOT_TYPE"
  info "Root size: ${ROOT_GB}GB"

  # Confirm
  warn "WARNING: This will ERASE $DISK"
  read -p "Continue? (yes/no): " confirm
  [[ "$confirm" != "yes" ]] && die "Partitioning cancelled"

  # Wipe existing partition table
  info "Wiping existing partition table..."
  wipefs -a "$DISK" || die "Failed to wipe disk"
  sync

  if [[ "$BOOT_TYPE" == "uefi" ]]; then
    partition_uefi
  else
    partition_bios
  fi

  success "Disk partitioned successfully"
  record OK "disk partitioning" "$DISK"
}

partition_uefi() {
  info "Creating GPT partition table for UEFI..."

  # Create GPT partition table
  parted -s "$DISK" mklabel gpt || die "Failed to create GPT table"

  # EFI System Partition (512MB)
  parted -s "$DISK" mkpart primary fat32 1MiB 513MiB || die "Failed to create EFI partition"
  parted -s "$DISK" set 1 esp on || die "Failed to set ESP flag"

  # Root partition
  local end_root=$((513 + ROOT_GB * 1024))
  parted -s "$DISK" mkpart primary ext4 513MiB "${end_root}MiB" || die "Failed to create root partition"

  # Swap partition (remaining space)
  parted -s "$DISK" mkpart primary linux-swap "${end_root}MiB" 100% || die "Failed to create swap partition"

  sync
  sleep 2

  # Detect partition names
  detect_partitions_uefi
}

partition_bios() {
  info "Creating MBR partition table for BIOS..."

  # Create MBR partition table
  parted -s "$DISK" mklabel msdos || die "Failed to create MBR table"

  # Root partition
  local end_root=$((1 + ROOT_GB * 1024))
  parted -s "$DISK" mkpart primary ext4 1MiB "${end_root}MiB" || die "Failed to create root partition"
  parted -s "$DISK" set 1 boot on || die "Failed to set boot flag"

  # Swap partition (remaining space)
  parted -s "$DISK" mkpart primary linux-swap "${end_root}MiB" 100% || die "Failed to create swap partition"

  sync
  sleep 2

  # Detect partition names
  detect_partitions_bios
}

detect_partitions_uefi() {
  info "Detecting partition names..."

  if [[ "$DISK" =~ nvme ]]; then
    PEFI="${DISK}p1"
    PROOT="${DISK}p2"
    PSWAP="${DISK}p3"
  else
    PEFI="${DISK}1"
    PROOT="${DISK}2"
    PSWAP="${DISK}3"
  fi

  [[ ! -b "$PEFI" ]] && die "EFI partition not found: $PEFI"
  [[ ! -b "$PROOT" ]] && die "Root partition not found: $PROOT"
  [[ ! -b "$PSWAP" ]] && die "Swap partition not found: $PSWAP"

  info "EFI:  $PEFI"
  info "Root: $PROOT"
  info "Swap: $PSWAP"

  # Save to config
  sed -i "s|^PEFI=.*|PEFI=\"$PEFI\"|" "$CONFIG_FILE"
  sed -i "s|^PROOT=.*|PROOT=\"$PROOT\"|" "$CONFIG_FILE"
  sed -i "s|^PSWAP=.*|PSWAP=\"$PSWAP\"|" "$CONFIG_FILE"
}

detect_partitions_bios() {
  info "Detecting partition names..."

  if [[ "$DISK" =~ nvme ]]; then
    PROOT="${DISK}p1"
    PSWAP="${DISK}p2"
  else
    PROOT="${DISK}1"
    PSWAP="${DISK}2"
  fi

  [[ ! -b "$PROOT" ]] && die "Root partition not found: $PROOT"
  [[ ! -b "$PSWAP" ]] && die "Swap partition not found: $PSWAP"

  info "Root: $PROOT"
  info "Swap: $PSWAP"

  # Save to config
  sed -i "s|^PROOT=.*|PROOT=\"$PROOT\"|" "$CONFIG_FILE"
  sed -i "s|^PSWAP=.*|PSWAP=\"$PSWAP\"|" "$CONFIG_FILE"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_root
  partition_disk
fi
