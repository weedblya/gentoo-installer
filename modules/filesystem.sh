#!/usr/bin/env bash
# =============================================================================
# Filesystem Creation Module
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

create_filesystems() {
  step "Creating Filesystems"

  load_config

  [[ -z "$PROOT" ]] && die "PROOT variable not set"

  # Create EFI filesystem if UEFI
  if [[ "$BOOT_TYPE" == "uefi" ]] && [[ -n "$PEFI" ]]; then
    info "Creating FAT32 filesystem on $PEFI..."
    mkfs.vfat -F32 "$PEFI" || die "Failed to create EFI filesystem"
    record OK "EFI filesystem" "$PEFI"
  fi

  # Create root filesystem
  info "Creating $FS_TYPE filesystem on $PROOT..."
  case "$FS_TYPE" in
    ext4)
      mkfs.ext4 -F "$PROOT" || die "Failed to create ext4 filesystem"
      ;;
    xfs)
      mkfs.xfs -f "$PROOT" || die "Failed to create xfs filesystem"
      ;;
    btrfs)
      mkfs.btrfs -f "$PROOT" || die "Failed to create btrfs filesystem"
      ;;
    *)
      die "Unsupported filesystem: $FS_TYPE"
      ;;
  esac
  record OK "root filesystem" "$PROOT ($FS_TYPE)"

  # Create swap
  if [[ -n "$PSWAP" ]]; then
    info "Creating swap on $PSWAP..."
    mkswap "$PSWAP" || die "Failed to create swap"
    swapon "$PSWAP" || die "Failed to enable swap"
    record OK "swap" "$PSWAP"
  fi

  success "Filesystems created successfully"
}

mount_filesystems() {
  step "Mounting Filesystems"

  load_config

  [[ -z "$PROOT" ]] && die "PROOT variable not set"

  # Create mount point
  mkdir -p "$MNT" || die "Failed to create mount point"

  # Mount root
  info "Mounting root partition $PROOT to $MNT..."
  mount "$PROOT" "$MNT" || die "Failed to mount root"
  MOUNTS_ACTIVE=1
  record OK "mount root" "$PROOT -> $MNT"

  # Mount EFI if UEFI
  if [[ "$BOOT_TYPE" == "uefi" ]] && [[ -n "$PEFI" ]]; then
    mkdir -p "$MNT/boot/efi" || die "Failed to create EFI mount point"
    info "Mounting EFI partition $PEFI to $MNT/boot/efi..."
    mount "$PEFI" "$MNT/boot/efi" || die "Failed to mount EFI"
    record OK "mount EFI" "$PEFI -> $MNT/boot/efi"
  fi

  success "Filesystems mounted successfully"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_root
  create_filesystems
  mount_filesystems
fi
