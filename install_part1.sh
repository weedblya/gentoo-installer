#!/bin/bash
# Gentoo Automated Installer - Part 1 (Improved)
# This script runs from the Gentoo Live ISO before chroot
# It handles partitioning, Stage 3 download, and initial setup

set -Eeuo pipefail

# ============================================
# Configuration and initialization
# ============================================

LOG="/tmp/gentoo-install-part1-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

TARGET="/mnt/gentoo"
DIST="https://distfiles.gentoo.org/releases/amd64/autobuilds"
SCRIPT_DIR="$(dirname -- "$(readlink -f -- "$0")")"

# Minimum requirements
MIN_RAM_MB=2048
MIN_DISK_GB=20

# ============================================
# Utility functions
# ============================================

die() {
    echo "[FATAL] $*" >&2
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

confirm() {
    local prompt="$1" ans
    read -r -p "$prompt [yes/NO]: " ans
    [[ "$ans" == "yes" ]]
}

check_requirements() {
    echo "Checking system requirements..."

    # Check RAM
    local ram_mb
    ram_mb="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
    if (( ram_mb < MIN_RAM_MB )); then
        die "Insufficient RAM: ${ram_mb}MB (minimum ${MIN_RAM_MB}MB required)"
    fi
    echo "  RAM: ${ram_mb}MB ✓"

    # Check network connectivity
    if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        die "No network connectivity. Please check your connection."
    fi
    echo "  Network: connected ✓"

    # Check DNS
    if ! ping -c 1 -W 5 gentoo.org >/dev/null 2>&1; then
        echo "[WARN] DNS may not be working properly"
    else
        echo "  DNS: working ✓"
    fi
}

# ============================================
# Disk cleanup and partition management
# ============================================

cleanup_disk_state() {
    local disk="$1"
    local part target
    echo "Releasing old mount/swap state for $disk..."

    # Unmount every mounted partition belonging to the selected disk
    while read -r part; do
        [[ -n "$part" ]] || continue
        while read -r target; do
            [[ -n "$target" ]] || continue
            echo "  Unmounting: $target"
            umount "$target" 2>/dev/null || umount -l "$target" 2>/dev/null || true
        done < <(findmnt -rn -S "$part" -o TARGET 2>/dev/null || true)
    done < <(lsblk -nrpo NAME,TYPE "$disk" | awk '$2=="part"{print $1}')

    # Disable any active swap partitions on this disk
    while read -r part; do
        [[ -n "$part" ]] || continue
        if grep -qE "^$part " /proc/swaps 2>/dev/null; then
            echo "  Disabling swap: $part"
            swapoff "$part" || true
        fi
    done < <(lsblk -nrpo NAME,TYPE "$disk" | awk '$2=="part"{print $1}')

    sync
    sleep 1
}

reread_partition_table() {
    local disk="$1"
    echo "Refreshing kernel partition table..."
    partprobe "$disk" 2>/dev/null || true
    partx -u "$disk" 2>/dev/null || true
    udevadm settle 2>/dev/null || true
    sleep 2
}

validate_disk() {
    local disk="$1"

    # Check if it's a block device
    [[ -b "$disk" ]] || die "Not a block device: $disk"

    # Check if it's a whole disk, not a partition
    [[ "$(lsblk -dn -o TYPE "$disk")" == "disk" ]] || die "A whole disk is required, not a partition."

    # Check disk size
    local size_gb
    size_gb="$(lsblk -dn -o SIZE -b "$disk" | awk '{print int($1/1024/1024/1024)}')"
    if (( size_gb < MIN_DISK_GB )); then
        die "Disk too small: ${size_gb}GB (minimum ${MIN_DISK_GB}GB required)"
    fi
    echo "  Disk size: ${size_gb}GB ✓"
}

# ============================================
# Main installation logic
# ============================================

echo
echo "=============================================="
echo " Gentoo Automated Installer — PART 1"
echo " Before chroot: partitioning + Stage 3 + fstab"
echo "=============================================="
echo

# Root check
[[ $EUID -eq 0 ]] || die "This script must be run as root."

# UEFI check
[[ -d /sys/firmware/efi ]] || die "System not booted in UEFI mode. This installer requires UEFI."

# Check required tools
for cmd in awk curl findmnt lsblk mount umount mkfs.fat mkfs.ext4 mkswap swapoff sfdisk partprobe partx udevadm wipefs blkid tar sha256sum sed grep; do
    need "$cmd"
done

# Check system requirements
check_requirements

echo
echo "Available block devices:"
lsblk -e7 -o NAME,SIZE,TYPE,FSTYPE,FSVER,LABEL,MOUNTPOINTS,MODEL

echo
read -r -p "Installation disk (e.g. /dev/nvme0n1 or /dev/sda): " DISK
validate_disk "$DISK"

echo
echo "Profile selection:"
echo "  1) gentoo_base     - Base desktop-ready system (no WM/DE)"
echo "  2) gentoo_niri     - Base + Niri compositor + Waybar"
echo "  3) gentoo_hyprland - Base + Hyprland + Waybar"
echo "  4) gentoo_kde      - Base + KDE Plasma desktop environment"
select PROFILE in gentoo_base gentoo_niri gentoo_hyprland gentoo_kde; do
    [[ -n "${PROFILE:-}" ]] && break
done

echo
echo "Init system:"
select INIT in systemd OpenRC; do
    [[ -n "${INIT:-}" ]] && break
done

echo
echo "GPU vendor:"
select GPU in NVIDIA AMD Intel; do
    [[ -n "${GPU:-}" ]] && break
done

echo
echo "Kernel type:"
echo "  1) distribution-kernel    - Gentoo binary kernel (fast, recommended)"
echo "  2) gentoo-kernel          - Auto-configured source kernel (builds locally)"
echo "  3) gentoo-sources         - Manual kernel configuration (advanced)"
select KERNEL_TYPE in distribution-kernel gentoo-kernel gentoo-sources; do
    [[ -n "${KERNEL_TYPE:-}" ]] && break
done

echo
echo "Partitioning mode:"
select PARTMODE in automatic cfdisk fdisk parted; do
    [[ -n "${PARTMODE:-}" ]] && break
done

echo
echo "Selected configuration:"
echo "  Disk:    $DISK"
echo "  Profile: $PROFILE"
echo "  Init:    $INIT"
echo "  GPU:     $GPU"
echo "  Kernel:  $KERNEL_TYPE"
echo "  Mode:    $PARTMODE"
echo

# ============================================
# Partitioning
# ============================================

if [[ "$PARTMODE" == automatic ]]; then
    echo
    echo "Swap configuration:"
    select SWAP_CHOICE in yes no; do
        [[ -n "${SWAP_CHOICE:-}" ]] && break
    done

    if [[ "$SWAP_CHOICE" == yes ]]; then
        # Suggest swap size based on RAM
        local ram_gb
        ram_gb="$(awk '/MemTotal/ {print int($2/1024/1024)}' /proc/meminfo)"
        local suggested_swap="${ram_gb}G"
        if (( ram_gb >= 16 )); then
            suggested_swap="16G"
        fi

        read -r -p "Swap size (suggested: ${suggested_swap}, e.g. 8G, 16G): " SWAP_SIZE
        SWAP_SIZE="${SWAP_SIZE:-$suggested_swap}"
        SWAP_SIZE="${SWAP_SIZE// /}"
        [[ "$SWAP_SIZE" =~ ^[1-9][0-9]*[MG]$ ]] || die "Invalid swap size. Use format like 8G or 16G."
    else
        SWAP_SIZE="NONE"
    fi

    echo
    echo "WARNING: The following disk will be COMPLETELY ERASED:"
    echo "  $DISK"
    echo
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS "$DISK"
    echo
    confirm "Proceed with automatic partitioning?" || die "Operation cancelled by user."

    cleanup_disk_state "$DISK"
    umount -R "$TARGET" 2>/dev/null || true
    mkdir -p "$TARGET"

    echo "Wiping disk..."
    wipefs -af "$DISK"
    sfdisk --delete "$DISK" 2>/dev/null || true
    sync

    echo "Creating partition table..."
    if [[ "$SWAP_SIZE" == "NONE" ]]; then
        sfdisk "$DISK" <<EOF
label: gpt
,1G,U
,,L
EOF
    else
        sfdisk "$DISK" <<EOF
label: gpt
,1G,U
,$SWAP_SIZE,S
,,L
EOF
    fi
    reread_partition_table "$DISK"

    # Detect created partitions
    mapfile -t PARTS < <(lsblk -nrpo NAME,TYPE "$DISK" | awk '$2=="part"{print $1}')
    if [[ "$SWAP_SIZE" == "NONE" ]]; then
        [[ ${#PARTS[@]} -ge 2 ]] || die "Failed to detect EFI and root partitions."
        EFI="${PARTS[0]}"
        SWAP="NONE"
        ROOT="${PARTS[1]}"
    else
        [[ ${#PARTS[@]} -ge 3 ]] || die "Failed to detect EFI, swap and root partitions."
        EFI="${PARTS[0]}"
        SWAP="${PARTS[1]}"
        ROOT="${PARTS[2]}"
    fi

    echo
    echo "Automatic partitioning complete:"
    echo "  EFI:  $EFI  (1 GiB)"
    if [[ "$SWAP" == "NONE" ]]; then
        echo "  Swap: disabled"
    else
        echo "  Swap: $SWAP ($SWAP_SIZE)"
    fi
    echo "  Root: $ROOT (remaining space)"
else
    # Manual partitioning
    echo
    cleanup_disk_state "$DISK"
    echo "Starting $PARTMODE for manual partitioning..."
    echo "Create a GPT partition layout with:"
    echo "  - EFI System Partition (type: EF00 or EFI)"
    echo "  - Root partition (type: 8300 or Linux filesystem)"
    echo "  - Optional swap partition (type: 8200 or Linux swap)"
    echo
    echo "Press Enter to continue..."
    read -r

    case "$PARTMODE" in
        cfdisk) cfdisk "$DISK" ;;
        fdisk)  fdisk "$DISK" ;;
        parted) parted "$DISK" ;;
    esac

    reread_partition_table "$DISK"

    echo
    echo "Current partition layout:"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS "$DISK"
    echo

    read -r -p "EFI partition (e.g. ${DISK}p1 or ${DISK}1): " EFI
    read -r -p "ROOT partition (e.g. ${DISK}p2 or ${DISK}2): " ROOT
    read -r -p "SWAP partition (press Enter or type NONE to skip): " SWAP
    [[ -n "$SWAP" ]] || SWAP="NONE"

    # Validate partitions
    [[ -b "$EFI" ]] || die "EFI partition not found: $EFI"
    [[ -b "$ROOT" ]] || die "ROOT partition not found: $ROOT"
    [[ "$SWAP" == "NONE" || -b "$SWAP" ]] || die "SWAP partition not found: $SWAP"

    echo
    echo "Selected partitions:"
    echo "  EFI:  $EFI"
    echo "  ROOT: $ROOT"
    echo "  SWAP: $SWAP"
    echo
    confirm "These partitions will be formatted. Continue?" || die "Operation cancelled by user."
fi

# ============================================
# Filesystem creation
# ============================================

echo
echo "Creating filesystems..."
echo "  Formatting $EFI as FAT32..."
mkfs.fat -F 32 "$EFI"

echo "  Formatting $ROOT as ext4..."
mkfs.ext4 -F "$ROOT"

if [[ "$SWAP" != "NONE" ]]; then
    echo "  Setting up swap on $SWAP..."
    mkswap "$SWAP"
    swapon "$SWAP"
fi

# ============================================
# Mounting
# ============================================

echo
echo "Mounting filesystems..."
mkdir -p "$TARGET"
mount "$ROOT" "$TARGET"
mkdir -p "$TARGET/efi"
mount "$EFI" "$TARGET/efi"

# Create necessary directories
mkdir -p "$TARGET/var/cache/binpkgs" \
         "$TARGET/etc/portage/repos.conf" \
         "$TARGET/etc/portage/binrepos.conf"

# ============================================
# Stage 3 download and extraction
# ============================================

case "$INIT" in
    systemd) STAGE_DIR="current-stage3-amd64-systemd"; BIN_PROFILE="23.0/x86-64" ;;
    OpenRC)  STAGE_DIR="current-stage3-amd64-openrc";  BIN_PROFILE="23.0/x86-64" ;;
esac

META_URL="$DIST/$STAGE_DIR/latest-stage3-amd64-${INIT,,}.txt"
TMPDIR="$(mktemp -d /tmp/gentoo-stage3.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

echo
echo "Downloading Stage 3 metadata..."
if ! curl -fL --retry 5 --retry-all-errors --connect-timeout 30 -o "$TMPDIR/latest.txt" "$META_URL"; then
    die "Failed to download Stage 3 metadata. Check your network connection."
fi

STAGE_FILE="$(awk '$1 ~ /^stage3-amd64-.*\.tar\.xz$/ {print $1; exit}' "$TMPDIR/latest.txt")"
[[ -n "$STAGE_FILE" ]] || die "Stage 3 file not found in metadata"

STAGE_URL="$DIST/$STAGE_DIR/$STAGE_FILE"
SHA_URL="$STAGE_URL.sha256"

echo "Downloading Stage 3 tarball: $STAGE_FILE"
echo "This may take several minutes..."
if ! curl -fL --retry 5 --retry-all-errors --connect-timeout 30 -o "$TMPDIR/$STAGE_FILE" "$STAGE_URL"; then
    die "Failed to download Stage 3 tarball"
fi

echo "Downloading checksum..."
if ! curl -fL --retry 5 --retry-all-errors --connect-timeout 30 -o "$TMPDIR/$STAGE_FILE.sha256" "$SHA_URL"; then
    die "Failed to download checksum"
fi

cd "$TMPDIR"
echo "Verifying SHA256 checksum..."
if ! sha256sum -c "$STAGE_FILE.sha256"; then
    die "SHA256 checksum verification failed!"
fi
echo "Checksum verification: PASSED ✓"

echo "Extracting Stage 3 (this may take a while)..."
if ! tar xpf "$TMPDIR/$STAGE_FILE" -C "$TARGET" --xattrs-include='*.*' --numeric-owner; then
    die "Failed to extract Stage 3"
fi

# ============================================
# Portage configuration
# ============================================

echo "Configuring Portage..."

cat > "$TARGET/etc/portage/repos.conf/gentoo.conf" <<'EOF'
[gentoo]
location = /var/db/repos/gentoo
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
auto-sync = yes
sync-webrsync-verify-signature = true
EOF

cat > "$TARGET/etc/portage/binrepos.conf/gentoobinhost.conf" <<EOF
[binhost]
priority = 9999
sync-uri = https://distfiles.gentoo.org/releases/amd64/binpackages/${BIN_PROFILE}/
EOF

# ============================================
# fstab generation
# ============================================

echo "Generating /etc/fstab..."
mkdir -p "$TARGET/etc"

cat > "$TARGET/etc/fstab" <<EOF
# /etc/fstab: static filesystem information
# Generated by Gentoo Installer on $(date)
#
# <fs>                                          <mountpoint>    <type>  <opts>              <dump/pass>
UUID=$(blkid -s UUID -o value "$ROOT")          /               ext4    defaults,noatime    0 1
UUID=$(blkid -s UUID -o value "$EFI")           /efi            vfat    defaults,noatime    0 2
EOF

if [[ "$SWAP" != "NONE" ]]; then
    echo "UUID=$(blkid -s UUID -o value "$SWAP")          none            swap    sw                  0 0" >> "$TARGET/etc/fstab"
fi

# ============================================
# Save configuration
# ============================================

cat > "$TARGET/root/gentoo-installer.conf" <<EOF
# Gentoo Installer Configuration
# Generated on $(date)
PROFILE="$PROFILE"
INIT="$INIT"
GPU="$GPU"
KERNEL_TYPE="$KERNEL_TYPE"
DISK="$DISK"
EFI="$EFI"
ROOT="$ROOT"
SWAP="$SWAP"
STAGE3="$STAGE_FILE"
EOF

# Copy part 2 script
[[ -f "$SCRIPT_DIR/install_part2.sh" ]] || die "install_part2.sh must be in the same directory as this script"
install -m 0755 "$SCRIPT_DIR/install_part2.sh" "$TARGET/root/install_part2.sh"

# Copy resolv.conf for network in chroot
if [[ -f /etc/resolv.conf ]]; then
    cp -L /etc/resolv.conf "$TARGET/etc/resolv.conf"
fi

# Save installation log
cp "$LOG" "$TARGET/root/gentoo-install-part1.log" || true

# ============================================
# Installation complete
# ============================================

echo
echo "=============================================="
echo " PART 1 COMPLETED SUCCESSFULLY"
echo "=============================================="
echo
echo "Installation summary:"
echo "  Disk:    $DISK"
echo "  Profile: $PROFILE"
echo "  Init:    $INIT"
echo "  EFI:     $EFI"
echo "  Root:    $ROOT"
echo "  Swap:    $SWAP"
echo
echo "Next steps:"
echo "  1. Mount virtual filesystems and enter chroot:"
echo
cat <<'CHROOT_COMMANDS'
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --rbind /run /mnt/gentoo/run
mount --make-rslave /mnt/gentoo/run
chroot /mnt/gentoo /bin/bash
source /etc/profile
/root/install_part2.sh
CHROOT_COMMANDS
echo
echo "Log saved to: $LOG"
echo "Log copied to: $TARGET/root/gentoo-install-part1.log"
echo
